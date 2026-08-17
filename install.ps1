#requires -Version 7.4

[CmdletBinding()]
param(
    [switch]$Global,
    [switch]$Project,
    [string]$Tools,
    [string]$ProjectTypes,
    [string]$Technologies,
    [ValidateSet('terraform', 'databricks', 'fabric')]
    [string]$Profile,
    [string]$Client,
    [string]$Prefix,
    [switch]$Force,
    [switch]$Help,
    [Parameter(DontShow)]
    [switch]$Local
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Version = '3.7.0'
$script:KnownTools = @('claude', 'codex', 'gemini', 'cursor', 'copilot')
$script:SelectedTools = @()
$script:OwnershipFile = $null
$script:TemporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("mindflayer-{0}" -f [guid]::NewGuid().ToString('N'))
$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$script:ProjectMode = $null
$script:CanonicalProjectTypes = $null
$script:CanonicalTechnologies = $null
$script:EffectiveProfile = $null
$script:Manifest = @()
$script:OwnershipRoot = $null
$script:AllowedOwnershipRoots = @()
$script:OwnershipValidated = $false

function Write-Info {
    param([Parameter(Mandatory)][string]$Message)
    Write-Output $Message
}

function Write-WarningMessage {
    param([Parameter(Mandatory)][string]$Message)
    [Console]::Error.WriteLine("! {0}" -f $Message)
}

function Stop-Installation {
    param([Parameter(Mandatory)][string]$Message)
    throw "error: $Message"
}

function ConvertTo-LfText {
    param([AllowEmptyString()][string]$Text)
    return $Text.Replace("`r`n", "`n").Replace("`r", "`n")
}

function Write-LfFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [AllowEmptyString()][string]$Content
    )

    $parent = Split-Path -Parent $Path
    if ($parent) {
        [System.IO.Directory]::CreateDirectory($parent) | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, (ConvertTo-LfText $Content), $script:Utf8NoBom)
}

function Get-NormalizedFileText {
    param([Parameter(Mandatory)][string]$Path)
    return ConvertTo-LfText ([System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8))
}

function Get-CksumProof {
    param([Parameter(Mandatory)][string]$Path)

    [byte[]]$bytes = [System.IO.File]::ReadAllBytes($Path)
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

function Get-TimeStamp {
    return [DateTime]::Now.ToString('yyyyMMddHHmmss', [Globalization.CultureInfo]::InvariantCulture)
}

function Get-BackupPath {
    param([Parameter(Mandatory)][string]$Path)

    $stamp = Get-TimeStamp
    $candidate = "$Path.bak.$stamp"
    $suffix = 0
    while (Test-Path -LiteralPath $candidate) {
        $suffix++
        $candidate = "$Path.bak.$stamp.$suffix"
    }
    return $candidate
}

function Get-ItemIfPresent {
    param([Parameter(Mandatory)][string]$Path)
    return Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
}

function Test-PathWithinRoot {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Root
    )

    $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if ($fullPath.Equals($fullRoot, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    $prefix = $fullRoot + [IO.Path]::DirectorySeparatorChar
    return $fullPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

function Assert-NoReparseAncestor {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Root
    )

    # Matches canonicalize_owned_path in install.sh: every directory above the managed path is
    # resolved strictly, while the leaf itself may be a link the toolkit owns, such as a skill
    # junction created by an earlier install.
    $fullPath = [IO.Path]::GetFullPath($Path)
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $current = Split-Path -Parent $fullPath
    while ($current -and (Test-PathWithinRoot -Path $current -Root $fullRoot)) {
        $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
        if ($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            Stop-Installation "managed path crosses a reparse point: $current"
        }
        if ($current.TrimEnd([IO.Path]::DirectorySeparatorChar).Equals($fullRoot, [StringComparison]::OrdinalIgnoreCase)) { break }
        $current = Split-Path -Parent $current
    }
}

function Resolve-ManagedPath {
    param(
        [Parameter(Mandatory)][string]$RecordedPath,
        [switch]$SkipReparseCheck
    )

    if (-not $RecordedPath -or $RecordedPath.Contains("`r") -or $RecordedPath.Contains("`n") -or $RecordedPath.Contains("`t")) {
        Stop-Installation 'ownership record contains an invalid path'
    }
    $candidate = if ([IO.Path]::IsPathRooted($RecordedPath)) {
        [IO.Path]::GetFullPath($RecordedPath)
    }
    else {
        [IO.Path]::GetFullPath((Join-Path $script:OwnershipRoot $RecordedPath))
    }
    foreach ($allowedRoot in $script:AllowedOwnershipRoots) {
        if (Test-PathWithinRoot -Path $candidate -Root $allowedRoot) {
            if (-not $SkipReparseCheck) {
                Assert-NoReparseAncestor -Path $candidate -Root $allowedRoot
            }
            return $candidate
        }
    }
    Stop-Installation "managed path is outside the allowed installation roots: $RecordedPath"
}

function Assert-OwnershipFileSafe {
    if (-not $script:OwnershipFile) { return }
    $item = Get-Item -LiteralPath $script:OwnershipFile -Force -ErrorAction SilentlyContinue
    if ($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        Stop-Installation "ownership record must not be a reparse point: $script:OwnershipFile"
    }
}

function Write-OwnershipFile {
    param([AllowEmptyString()][string]$Content)
    Assert-OwnershipFileSafe
    $parent = Split-Path -Parent $script:OwnershipFile
    [IO.Directory]::CreateDirectory($parent) | Out-Null
    $temporaryPath = Join-Path $parent (".{0}.{1}.tmp" -f ([IO.Path]::GetFileName($script:OwnershipFile)), [guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllText($temporaryPath, (ConvertTo-LfText $Content), $script:Utf8NoBom)
        [IO.File]::Move($temporaryPath, $script:OwnershipFile, $true)
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
    }
}

function Backup-And-RemoveItem {
    param([Parameter(Mandatory)][string]$Path)

    $item = Get-ItemIfPresent $Path
    if ($null -eq $item) {
        return
    }

    $backup = Get-BackupPath $Path
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -and $item.LinkType -eq 'Junction') {
        New-Item -ItemType Junction -Path $backup -Target $item.Target | Out-Null
    }
    elseif ($item.PSIsContainer) {
        Copy-Item -LiteralPath $Path -Destination $backup -Recurse
    }
    else {
        Copy-Item -LiteralPath $Path -Destination $backup
    }
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        Remove-Item -LiteralPath $Path -Force
    }
    else {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
    Write-Info " b $backup"
}

function Get-OwnershipRecords {
    Assert-OwnershipFileSafe
    if (-not $script:OwnershipFile -or -not (Test-Path -LiteralPath $script:OwnershipFile -PathType Leaf)) {
        $script:OwnershipValidated = $true
        return @()
    }
    $shouldValidatePaths = -not $script:OwnershipValidated

    $records = foreach ($line in [System.IO.File]::ReadAllLines($script:OwnershipFile, [System.Text.Encoding]::UTF8)) {
        if (-not $line) { continue }
        $fields = $line.Split("`t", 3)
        if ($fields.Count -ne 3 -or -not @('file', 'junction', 'directory', 'line').Contains($fields[1])) {
            Stop-Installation "invalid ownership record in $script:OwnershipFile"
        }
        $fullPath = Resolve-ManagedPath -RecordedPath $fields[0] -SkipReparseCheck:(-not $shouldValidatePaths)
        [pscustomobject]@{ Path = $fields[0]; FullPath = $fullPath; Kind = $fields[1]; Proof = $fields[2] }
    }
    $script:OwnershipValidated = $true
    return @($records)
}

function Test-OwnershipRecorded {
    param([Parameter(Mandatory)][string]$Path)
    return [bool](Get-OwnershipRecords | Where-Object { $_.Path -eq $Path } | Select-Object -First 1)
}

function Set-OwnershipRecord {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][ValidateSet('file', 'junction', 'directory', 'line')][string]$Kind,
        [Parameter(Mandatory)][string]$Proof
    )

    if (-not $script:OwnershipFile) { return }
    [void](Resolve-ManagedPath -RecordedPath $Path)
    Assert-OwnershipFileSafe
    $parent = Split-Path -Parent $script:OwnershipFile
    if ($parent) { [System.IO.Directory]::CreateDirectory($parent) | Out-Null }

    $remaining = Get-OwnershipRecords | Where-Object {
        if ($Kind -eq 'line') {
            -not ($_.Path -eq $Path -and $_.Kind -eq $Kind -and $_.Proof -eq $Proof)
        }
        else {
            $_.Path -ne $Path
        }
    }
    $lines = @($remaining | ForEach-Object { "{0}`t{1}`t{2}" -f $_.Path, $_.Kind, $_.Proof })
    $lines += "{0}`t{1}`t{2}" -f $Path, $Kind, $Proof
    Write-OwnershipFile -Content (($lines -join "`n") + "`n")
}

function Remove-OwnershipRecord {
    param([Parameter(Mandatory)][string]$Path)
    if (-not $script:OwnershipFile -or -not (Test-Path -LiteralPath $script:OwnershipFile -PathType Leaf)) { return }
    $remaining = Get-OwnershipRecords | Where-Object { $_.Path -ne $Path }
    $content = if ($remaining.Count -gt 0) {
        (($remaining | ForEach-Object { "{0}`t{1}`t{2}" -f $_.Path, $_.Kind, $_.Proof }) -join "`n") + "`n"
    }
    else { '' }
    Write-OwnershipFile -Content $content
}

function Install-File {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [string]$Label = $Destination
    )

    $sourceText = Get-NormalizedFileText $Source
    $existing = Get-ItemIfPresent $Destination
    if ($null -ne $existing -and -not $existing.PSIsContainer) {
        $destinationText = Get-NormalizedFileText $Destination
        if ($sourceText -ceq $destinationText) {
            Write-Info " = $Label"
            if (Test-OwnershipRecorded $Destination) {
                Set-OwnershipRecord -Path $Destination -Kind file -Proof (Get-CksumProof $Destination)
            }
            return
        }
    }

    if ($null -ne $existing) {
        if (-not $Force) {
            Write-WarningMessage "preserved $Label (use -Force to replace)"
            return
        }
        Backup-And-RemoveItem $Destination
    }

    Write-LfFile -Path $Destination -Content $sourceText
    Set-OwnershipRecord -Path $Destination -Kind file -Proof (Get-CksumProof $Destination)
    Write-Info " + $Label"
}

function Test-IsJunctionTo {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Target
    )
    $item = Get-ItemIfPresent $Path
    if ($null -eq $item -or $item.LinkType -ne 'Junction') { return $false }
    $actual = [System.IO.Path]::GetFullPath([string]$item.Target)
    $expected = [System.IO.Path]::GetFullPath($Target)
    return $actual.Equals($expected, [StringComparison]::OrdinalIgnoreCase)
}

function Install-Junction {
    param(
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$Link
    )

    $parent = Split-Path -Parent $Link
    [System.IO.Directory]::CreateDirectory($parent) | Out-Null
    if (Test-IsJunctionTo -Path $Link -Target $Target) {
        Write-Info " = $Link"
        if (Test-OwnershipRecorded $Link) {
            Set-OwnershipRecord -Path $Link -Kind junction -Proof ([System.IO.Path]::GetFullPath($Target))
        }
        return
    }

    if ($null -ne (Get-ItemIfPresent $Link)) {
        if (-not $Force) {
            Write-WarningMessage "preserved $Link (use -Force to replace)"
            return
        }
        Backup-And-RemoveItem $Link
    }

    if (-not $IsWindows) {
        Stop-Installation 'global skill installation requires Windows NTFS directory junctions'
    }
    New-Item -ItemType Junction -Path $Link -Target $Target | Out-Null
    if (-not (Test-IsJunctionTo -Path $Link -Target $Target)) {
        Stop-Installation "failed to verify junction $Link"
    }
    Set-OwnershipRecord -Path $Link -Kind junction -Proof ([System.IO.Path]::GetFullPath($Target))
    Write-Info " + $Link -> $Target"
}

function ConvertTo-NativeScriptPath {
    param([Parameter(Mandatory)][string]$ManifestPath)
    return $ManifestPath
}

function Get-SourceFile {
    param([Parameter(Mandatory)][string]$Path)

    $nativePath = ConvertTo-NativeScriptPath $Path
    $destination = Join-Path $script:TemporaryRoot ($nativePath.Replace('/', [IO.Path]::DirectorySeparatorChar))
    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $destination)) | Out-Null
    $source = Join-Path $PSScriptRoot ($nativePath.Replace('/', [IO.Path]::DirectorySeparatorChar))
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        Stop-Installation "bundle source not found: $source"
    }
    Copy-Item -LiteralPath $source -Destination $destination
    return $destination
}

function Read-Manifest {
    param([Parameter(Mandatory)][string]$Path)
    $allowedTypes = @('baseline', 'decision', 'document', 'license', 'manifest', 'registry', 'script', 'setting', 'shim', 'skill', 'skill-resource', 'template')
    $allowedOwnership = @('managed-file', 'managed-tree')
    $allowedConsumers = @('global', 'global:claude', 'global:codex', 'global:copilot', 'global:cursor', 'global:gemini', 'project', 'project:claude', 'project:claude:databricks', 'project:claude:fabric', 'project:claude:terraform', 'project:gemini', 'project:skills')
    $seenPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $rows = foreach ($line in [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)) {
        if (-not $line -or $line.StartsWith('#')) { continue }
        $fields = $line.Split("`t")
        if ($fields.Count -ne 6) {
            Stop-Installation 'manifest.tsv must contain exactly six fields per row'
        }
        $manifestPath = $fields[0]
        if (-not $manifestPath -or [IO.Path]::IsPathRooted($manifestPath) -or $manifestPath.Contains('\') -or
            $manifestPath.Contains("`r") -or $manifestPath.Contains("`n") -or
            @($manifestPath.Split('/') | Where-Object { -not $_ -or $_ -eq '.' -or $_ -eq '..' }).Count -gt 0) {
            Stop-Installation "manifest.tsv contains an unsafe path: $manifestPath"
        }
        if (-not $seenPaths.Add($manifestPath)) {
            Stop-Installation "manifest.tsv contains a duplicate path: $manifestPath"
        }
        if (-not $allowedTypes.Contains($fields[1])) { Stop-Installation "manifest.tsv contains invalid type for $manifestPath" }
        if (-not $fields[2]) { Stop-Installation "manifest.tsv contains an empty version for $manifestPath" }
        $consumers = $fields[3].Split(',')
        if ($consumers.Count -eq 0 -or $consumers -contains '' -or
            @($consumers | Sort-Object -Unique).Count -ne $consumers.Count -or
            @($consumers | Where-Object { -not $allowedConsumers.Contains($_) }).Count -gt 0) {
            Stop-Installation "manifest.tsv contains invalid consumers for $manifestPath"
        }
        if (-not $allowedOwnership.Contains($fields[4])) { Stop-Installation "manifest.tsv contains invalid ownership for $manifestPath" }
        $platforms = $fields[5].Split(',')
        if ($platforms.Count -eq 0 -or
            @($platforms | Sort-Object -Unique).Count -ne $platforms.Count -or
            @($platforms | Where-Object { -not @('linux', 'macos', 'windows').Contains($_) }).Count -gt 0) {
            Stop-Installation "manifest.tsv contains invalid platforms for $($fields[0])"
        }
        [pscustomobject]@{
            Path = $fields[0]
            Type = $fields[1]
            Version = $fields[2]
            Consumers = $fields[3]
            Ownership = $fields[4]
            Platforms = $fields[5]
        }
    }
    if (@($rows).Count -eq 0) { Stop-Installation 'manifest.tsv contains no artifacts' }
    return @($rows)
}

function Assert-ManifestSources {
    param([Parameter(Mandatory)][object[]]$Manifest)
    foreach ($row in $Manifest | Where-Object { $_.Path -eq 'manifest.tsv' -or (Test-PlatformMatch $_.Platforms) }) {
        $source = Join-Path $PSScriptRoot ($row.Path.Replace('/', [IO.Path]::DirectorySeparatorChar))
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            Stop-Installation "bundle source not found: $source"
        }
    }
}

function Test-ConsumerMatch {
    param([string]$Consumers, [string]$Wanted)
    return $Consumers.Split(',').Contains($Wanted)
}

function Test-PlatformMatch {
    param([Parameter(Mandatory)][string]$Platforms)
    return $Platforms.Split(',').Contains('windows')
}

function Test-GlobalConsumerSelected {
    param([string]$Consumers)
    foreach ($consumer in $Consumers.Split(',')) {
        if ($consumer -eq 'global') { return $true }
        if ($consumer.StartsWith('global:') -and $script:SelectedTools.Contains($consumer.Substring(7))) { return $true }
    }
    return $false
}

function Get-GlobalDestination {
    param([Parameter(Mandatory)][string]$ManifestPath)
    $path = ConvertTo-NativeScriptPath $ManifestPath
    $toolkitHome = Join-Path $HOME '.ai-toolkit'
    switch -Regex ($path) {
        '^(bootstrap|install)\.(sh|ps1)$' { return Join-Path $toolkitHome $path }
        '^(README\.md|how-to-guide\.md|LICENSE)$' { return Join-Path (Join-Path $toolkitHome 'docs') $path }
        '^global/AGENTS\.md$' { return Join-Path $toolkitHome 'AGENTS.md' }
        '^(CLAUDE\.md|GEMINI\.md)$' { return Join-Path (Join-Path $toolkitHome 'templates') $path }
        '^templates/' { return Join-Path $toolkitHome ($path.Replace('/', [IO.Path]::DirectorySeparatorChar)) }
        '^(config|docs|skills)/' { return Join-Path $toolkitHome ($path.Replace('/', [IO.Path]::DirectorySeparatorChar)) }
        '^tools/' { return Join-Path $toolkitHome ([IO.Path]::GetFileName($path)) }
        '^(stores\.yml|manifest\.tsv)$' { return Join-Path $toolkitHome $path }
        '^settings/claude/' { return Join-Path (Join-Path $toolkitHome 'templates/settings') ([IO.Path]::GetFileName($path)) }
        '^settings/codex/' { return Join-Path (Join-Path $toolkitHome 'templates/codex') ([IO.Path]::GetFileName($path)) }
        '^settings/gemini/' { return Join-Path (Join-Path $toolkitHome 'templates/gemini') ([IO.Path]::GetFileName($path)) }
        default { Stop-Installation "no global destination for manifest path $ManifestPath" }
    }
}

function Get-SelectedSkillRoots {
    param([ValidateSet('global', 'project')][string]$Scope)
    $records = @(
        [pscustomobject]@{ Tool = 'claude'; Scope = 'global'; Root = Join-Path $HOME '.claude/skills' }
        [pscustomobject]@{ Tool = 'codex'; Scope = 'global'; Root = Join-Path $HOME '.agents/skills' }
        [pscustomobject]@{ Tool = 'copilot'; Scope = 'global'; Root = Join-Path $HOME '.copilot/skills' }
        [pscustomobject]@{ Tool = 'claude'; Scope = 'project'; Root = '.claude/skills' }
        [pscustomobject]@{ Tool = 'codex'; Scope = 'project'; Root = '.agents/skills' }
        [pscustomobject]@{ Tool = 'copilot'; Scope = 'project'; Root = '.claude/skills' }
    )
    return @($records | Where-Object { $_.Scope -eq $Scope -and $script:SelectedTools.Contains($_.Tool) } |
        Select-Object -ExpandProperty Root -Unique)
}

function Get-CatalogRows {
    param([Parameter(Mandatory)][string]$Path)
    $rows = foreach ($line in [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)) {
        if (-not $line -or $line.StartsWith('#')) { continue }
        $fields = $line.Split("`t")
        while ($fields.Count -lt 5) { $fields += '' }
        [pscustomobject]@{ Id = $fields[0]; Type = $fields[1]; Ecosystem = $fields[2]; Aliases = $fields[3]; Description = $fields[4] }
    }
    return @($rows)
}

function Resolve-CatalogList {
    param(
        [Parameter(Mandatory)][string]$Value,
        [Parameter(Mandatory)][ValidateSet('project-type', 'technology')][string]$Group,
        [Parameter(Mandatory)][string]$Flag,
        [Parameter(Mandatory)][string]$CatalogPath
    )
    $eligible = Get-CatalogRows $CatalogPath | Where-Object {
        if ($Group -eq 'project-type') { $_.Type -eq 'project-type' } else { $_.Type -ne 'project-type' }
    }
    $resolved = [Collections.Generic.List[string]]::new()
    foreach ($rawToken in $Value.Split(',')) {
        $token = ($rawToken -replace '\s', '')
        if (-not $token) { Stop-Installation "$Flag contains an empty value" }
        if ($token -cne $token.ToLowerInvariant()) { Stop-Installation "$Flag value '$token' must be lowercase" }
        $row = $eligible | Where-Object {
            $_.Id -eq $token -or ($_.Aliases -and $_.Aliases -ne '-' -and $_.Aliases.Split(',').Contains($token))
        } | Select-Object -First 1
        if ($null -eq $row) {
            Stop-Installation "unknown $Flag value '$token'; expected one of: $((@($eligible.Id) -join ','))"
        }
        if ($resolved.Contains($row.Id)) { Stop-Installation "duplicate $Flag value '$($row.Id)'" }
        $resolved.Add($row.Id)
    }
    return (@($eligible.Id | Where-Object { $resolved.Contains($_) }) -join ',')
}

function New-ClaudeSettings {
    param(
        [Parameter(Mandatory)][string]$PolicyPath,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$TechnologyList
    )
    $selected = @($TechnologyList.Split(','))
    $rows = foreach ($line in [System.IO.File]::ReadAllLines($PolicyPath, [System.Text.Encoding]::UTF8)) {
        if (-not $line -or $line.StartsWith('#')) { continue }
        $fields = $line.Split("`t")
        if ($fields.Count -ge 3 -and $selected.Contains($fields[0]) -and @('allow', 'deny').Contains($fields[1])) {
            [pscustomobject]@{ Effect = $fields[1]; Pattern = $fields[2] }
        }
    }
    $denied = @($rows | Where-Object Effect -eq 'deny' | Select-Object -ExpandProperty Pattern -Unique)
    $allow = @($rows | Where-Object { $_.Effect -eq 'allow' -and -not $denied.Contains($_.Pattern) } |
        Select-Object -ExpandProperty Pattern -Unique)
    $settings = [ordered]@{ permissions = [ordered]@{ allow = $allow; deny = $denied } }
    Write-LfFile -Path $Destination -Content (($settings | ConvertTo-Json -Depth 4) + "`n")
}

function Expand-LegacyTemplate {
    param([string]$Source, [string]$Destination, [string]$ClientName, [string]$Platform, [string]$ResourcePrefix)
    $repositoryType = if ($Platform -eq 'terraform') { 'infrastructure' } else { 'data-platform' }
    $content = Get-NormalizedFileText $Source
    $content = $content.Replace('{CLIENT_NAME}', $ClientName).Replace('{PLATFORM}', $Platform)
    $content = $content.Replace('{REPO_TYPE}', $repositoryType).Replace('{prefix}', $ResourcePrefix)
    Write-LfFile -Path $Destination -Content $content
}

function Expand-ComposableTemplate {
    param([string]$Source, [string]$Destination, [string]$ClientName, [string]$ProjectTypeList, [string]$TechnologyList, [string]$ResourcePrefix)
    $resourceLine = if ($ResourcePrefix) { '- **resource prefix:** `' + $ResourcePrefix + '`' } else { '' }
    $content = Get-NormalizedFileText $Source
    $content = $content.Replace('{CLIENT_NAME}', $ClientName)
    $content = $content.Replace('{PROJECT_TYPES}', ($ProjectTypeList -replace ',', ', '))
    $content = $content.Replace('{TECHNOLOGIES}', ($TechnologyList -replace ',', ', '))
    $content = $content.Replace('{RESOURCE_PREFIX_LINE}', $resourceLine)
    Write-LfFile -Path $Destination -Content $content
}

function Add-GitIgnoreLine {
    param([Parameter(Mandatory)][string]$Entry)
    $path = Join-Path (Get-Location).Path '.gitignore'
    [string[]]$lines = @()
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $lines = [System.IO.File]::ReadAllLines($path, [System.Text.Encoding]::UTF8)
    }
    if ($lines -contains $Entry) { return }
    $lines += $Entry
    Write-LfFile -Path $path -Content (($lines -join "`n") + "`n")
    Set-OwnershipRecord -Path $path -Kind line -Proof $Entry
}

function Remove-VerifiedOwnedArtifact {
    param([Parameter(Mandatory)][string]$Path)
    $fullPath = Resolve-ManagedPath -RecordedPath $Path
    $record = Get-OwnershipRecords | Where-Object { $_.FullPath.Equals($fullPath, [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
    if ($null -eq $record) { return }
    $item = Get-ItemIfPresent $record.FullPath
    if ($null -eq $item) {
        Remove-OwnershipRecord $record.Path
        return
    }
    if ($record.Kind -eq 'file') {
        if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or (Get-CksumProof $record.FullPath) -ne $record.Proof) {
            Write-WarningMessage "preserved obsolete $($record.Path) (modified or type changed)"
            return
        }
    }
    elseif ($record.Kind -eq 'junction') {
        if (-not (Test-IsJunctionTo -Path $record.FullPath -Target $record.Proof)) {
            Write-WarningMessage "preserved obsolete $($record.Path) (target changed)"
            return
        }
    }
    else {
        Write-WarningMessage "preserved obsolete $($record.Path) (unsupported ownership class)"
        return
    }
    if ($record.Kind -eq 'junction') {
        Remove-Item -LiteralPath $record.FullPath -Force
    }
    else {
        Remove-Item -LiteralPath $record.FullPath -Recurse -Force
    }
    Remove-OwnershipRecord $record.Path
    Write-Info " - $($record.Path) (obsolete)"
}

function Remove-ObsoleteSkillFiles {
    param(
        [Parameter(Mandatory)][object[]]$Manifest,
        [Parameter(Mandatory)][string]$Root
    )
    $expected = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($row in $Manifest) {
        if (-not @('skill', 'skill-resource').Contains($row.Type) -or
            -not (Test-ConsumerMatch $row.Consumers 'project:skills') -or
            -not (Test-PlatformMatch $row.Platforms)) {
            continue
        }
        $relative = $row.Path.Substring('skills/'.Length).Replace('/', [IO.Path]::DirectorySeparatorChar)
        [void]$expected.Add((Resolve-ManagedPath -RecordedPath (Join-Path $Root $relative)))
    }
    $fullRoot = Resolve-ManagedPath -RecordedPath $Root
    foreach ($record in @(Get-OwnershipRecords)) {
        if ((Test-PathWithinRoot -Path $record.FullPath -Root $fullRoot) -and
            -not $expected.Contains($record.FullPath)) {
            Remove-VerifiedOwnedArtifact $record.Path
        }
    }
}

function Remove-ObsoleteOwnedArtifacts {
    param([Parameter(Mandatory)][string[]]$ExpectedPaths)

    $expected = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($path in $ExpectedPaths) {
        [void]$expected.Add((Resolve-ManagedPath -RecordedPath $path))
    }
    foreach ($record in @(Get-OwnershipRecords)) {
        if (@('file', 'junction').Contains($record.Kind) -and -not $expected.Contains($record.FullPath)) {
            Remove-VerifiedOwnedArtifact $record.Path
        }
    }
}

function Remove-LegacyProjectArtifacts {
    param([Parameter(Mandatory)][string]$Consumer)
    $paths = switch ($Consumer) {
        'claude' { @('.claude/rules/README.md', '.claude/commands/README.md', '.claude/agents/README.md', '.claude/hooks/README.md') }
        'codex' { @('codex.md') }
        'gemini' { @('gemini.md') }
        'cursor' { @('.cursor/rules/project.md') }
        'copilot' { @('.github/copilot-instructions.md') }
    }
    foreach ($path in $paths) { Remove-VerifiedOwnedArtifact $path }
}

function Install-GlobalToolkit {
    $toolkitHome = Join-Path $HOME '.ai-toolkit'
    $toolkitRoot = Get-ItemIfPresent $toolkitHome
    if ($null -ne $toolkitRoot -and ($toolkitRoot.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        Stop-Installation "global toolkit root must not be a reparse point: $toolkitHome"
    }
    $script:OwnershipRoot = [IO.Path]::GetFullPath($HOME)
    $script:AllowedOwnershipRoots = @(
        $toolkitHome,
        (Join-Path $HOME '.claude'),
        (Join-Path $HOME '.codex'),
        (Join-Path $HOME '.gemini'),
        (Join-Path $HOME '.cursor'),
        (Join-Path $HOME '.copilot'),
        (Join-Path $HOME '.agents')
    )
    $script:OwnershipFile = Join-Path $toolkitHome 'managed.tsv'
    $script:OwnershipValidated = $false
    Assert-OwnershipFileSafe
    [void](Get-OwnershipRecords)
    [System.IO.Directory]::CreateDirectory($toolkitHome) | Out-Null
    $manifestSource = Get-SourceFile 'manifest.tsv'
    Install-File -Source $manifestSource -Destination (Join-Path $toolkitHome 'manifest.tsv') -Label 'manifest.tsv'
    $manifest = $script:Manifest

    $expectedPaths = [Collections.Generic.List[string]]::new()
    $expectedPaths.Add((Join-Path $toolkitHome 'manifest.tsv'))
    $expectedPaths.Add((Join-Path $toolkitHome 'version'))
    foreach ($row in $manifest | Where-Object {
        $_.Path -ne 'manifest.tsv' -and (Test-GlobalConsumerSelected $_.Consumers) -and (Test-PlatformMatch $_.Platforms)
    }) {
        $expectedPaths.Add((Get-GlobalDestination $row.Path))
    }
    $consumerPaths = @{
        claude = @((Join-Path $HOME '.claude/CLAUDE.md'), (Join-Path $HOME '.claude/settings.json'))
        codex = @((Join-Path $HOME '.codex/AGENTS.md'))
        gemini = @((Join-Path $HOME '.gemini/GEMINI.md'))
        cursor = @((Join-Path $HOME '.cursor/rules.md'))
        copilot = @((Join-Path $HOME '.copilot/copilot-instructions.md'))
    }
    foreach ($tool in $script:SelectedTools) { foreach ($path in $consumerPaths[$tool]) { $expectedPaths.Add($path) } }
    $skillNames = @($manifest | Where-Object { $_.Type -eq 'skill' -and (Test-PlatformMatch $_.Platforms) } | ForEach-Object {
        $_.Path.Substring('skills/'.Length).Replace('/SKILL.md', '')
    })
    foreach ($root in Get-SelectedSkillRoots global) {
        foreach ($skillName in $skillNames) { $expectedPaths.Add((Join-Path $root $skillName)) }
    }
    Remove-ObsoleteOwnedArtifacts -ExpectedPaths $expectedPaths.ToArray()

    foreach ($row in $manifest) {
        if ($row.Path -eq 'manifest.tsv' -or
            -not (Test-GlobalConsumerSelected $row.Consumers) -or
            (Test-PlatformMatch $row.Platforms)) {
            continue
        }
        Remove-VerifiedOwnedArtifact (Get-GlobalDestination $row.Path)
    }
    Remove-ObsoleteSkillFiles -Manifest $manifest -Root (Join-Path $toolkitHome 'skills')

    foreach ($row in $manifest) {
        if ($row.Path -eq 'manifest.tsv' -or
            -not (Test-GlobalConsumerSelected $row.Consumers) -or
            -not (Test-PlatformMatch $row.Platforms)) {
            continue
        }
        $source = Get-SourceFile $row.Path
        $destination = Get-GlobalDestination $row.Path
        Install-File -Source $source -Destination $destination -Label (ConvertTo-NativeScriptPath $row.Path)
    }

    $baseline = Join-Path $toolkitHome 'AGENTS.md'
    foreach ($tool in $script:SelectedTools) {
        switch ($tool) {
            'claude' {
                Install-File $baseline (Join-Path $HOME '.claude/CLAUDE.md')
                Install-File (Get-SourceFile 'settings/claude/settings-global.json') (Join-Path $HOME '.claude/settings.json')
            }
            'codex' { Install-File $baseline (Join-Path $HOME '.codex/AGENTS.md') }
            'gemini' { Install-File $baseline (Join-Path $HOME '.gemini/GEMINI.md') }
            'cursor' { Install-File $baseline (Join-Path $HOME '.cursor/rules.md') }
            'copilot' { Install-File $baseline (Join-Path $HOME '.copilot/copilot-instructions.md') }
        }
    }

    foreach ($root in Get-SelectedSkillRoots global) {
        foreach ($skillName in $skillNames) {
            Install-Junction -Target (Join-Path $toolkitHome "skills/$skillName") -Link (Join-Path $root $skillName)
        }
    }

    $versionPath = Join-Path $toolkitHome 'version'
    Write-LfFile -Path $versionPath -Content ($script:Version + "`n")
    Set-OwnershipRecord -Path $versionPath -Kind file -Proof (Get-CksumProof $versionPath)
    Write-Info "Installed toolkit $($script:Version) for: $($script:SelectedTools -join ' ')"
}

function Get-ProjectMetadata {
    param([Parameter(Mandatory)][string]$AgentsPath)
    $content = Get-NormalizedFileText $AgentsPath
    $platformMatch = [regex]::Match($content, '(?m)^\s*- \*\*platform:\*\*\s*(.+?)\s*$')
    $typesMatch = [regex]::Match($content, '(?m)^\s*- \*\*project types:\*\*\s*(.+?)\s*$')
    $technologiesMatch = [regex]::Match($content, '(?m)^\s*- \*\*technologies:\*\*\s*(.+?)\s*$')
    return [pscustomobject]@{
        Platform = if ($platformMatch.Success) { $platformMatch.Groups[1].Value } else { '' }
        ProjectTypes = if ($typesMatch.Success) { $typesMatch.Groups[1].Value } else { '' }
        Technologies = if ($technologiesMatch.Success) { $technologiesMatch.Groups[1].Value } else { '' }
    }
}

function Install-ProjectToolkit {
    $current = (Get-Location).Path
    if ((Test-Path -LiteralPath (Join-Path $current 'manifest.tsv') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $current 'install.sh') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $current 'skills') -PathType Container)) {
        Stop-Installation 'the toolkit repository itself is not a valid -Project target'
    }

    $script:OwnershipRoot = [IO.Path]::GetFullPath($current)
    $script:AllowedOwnershipRoots = @($script:OwnershipRoot)
    $script:OwnershipFile = Join-Path $current '.mindflayer-managed.tsv'
    $script:OwnershipValidated = $false
    Assert-OwnershipFileSafe
    [void](Get-OwnershipRecords)
    $agentsPath = Join-Path $current 'AGENTS.md'
    $isJoin = $false
    if (Test-Path -LiteralPath $agentsPath -PathType Leaf) {
        $isJoin = (Get-NormalizedFileText $agentsPath).Contains('<!-- template: AGENTS | version:')
    }
    if ($Profile -and ($ProjectTypes -or $Technologies)) {
        Stop-Installation '-Profile cannot be combined with -ProjectTypes or -Technologies'
    }

    $catalogPath = $null
    if ($isJoin) {
        $metadata = Get-ProjectMetadata $agentsPath
        if ($metadata.ProjectTypes -or $metadata.Technologies) {
            if (-not $metadata.ProjectTypes -or -not $metadata.Technologies) {
                Stop-Installation 'AGENTS.md contains partial composable project metadata'
            }
            if ($Profile) { Stop-Installation '-Profile cannot be used with composable AGENTS.md metadata' }
            $catalogPath = Get-SourceFile 'config/technology-catalog.tsv'
            $storedTypes = Resolve-CatalogList $metadata.ProjectTypes project-type '-ProjectTypes' $catalogPath
            $storedTechnologies = Resolve-CatalogList $metadata.Technologies technology '-Technologies' $catalogPath
            $script:CanonicalProjectTypes = if ($ProjectTypes) { Resolve-CatalogList $ProjectTypes project-type '-ProjectTypes' $catalogPath } else { $storedTypes }
            $script:CanonicalTechnologies = if ($Technologies) { Resolve-CatalogList $Technologies technology '-Technologies' $catalogPath } else { $storedTechnologies }
            if ($script:CanonicalProjectTypes -ne $storedTypes) { Stop-Installation '-ProjectTypes does not match AGENTS.md' }
            if ($script:CanonicalTechnologies -ne $storedTechnologies) { Stop-Installation '-Technologies does not match AGENTS.md' }
            $script:ProjectMode = 'composable'
        }
        elseif ($metadata.Platform) {
            if ($ProjectTypes -or $Technologies) { Stop-Installation 'AGENTS.md contains legacy project metadata' }
            $effectiveProfile = if ($Profile) { $Profile } else { $metadata.Platform }
            if ($effectiveProfile -ne $metadata.Platform) { Stop-Installation '-Profile does not match AGENTS.md' }
            $script:ProjectMode = 'legacy'
            $script:EffectiveProfile = $effectiveProfile
        }
        else {
            Stop-Installation 'AGENTS.md has a toolkit template marker but no project metadata'
        }
    }
    elseif ($Profile) {
        $script:ProjectMode = 'legacy'
        $script:EffectiveProfile = $Profile
    }
    else {
        if (-not $ProjectTypes) { Stop-Installation '-ProjectTypes is required for a new project install' }
        if (-not $Technologies) { Stop-Installation '-Technologies is required for a new project install' }
        $catalogPath = Get-SourceFile 'config/technology-catalog.tsv'
        $script:CanonicalProjectTypes = Resolve-CatalogList $ProjectTypes project-type '-ProjectTypes' $catalogPath
        $script:CanonicalTechnologies = Resolve-CatalogList $Technologies technology '-Technologies' $catalogPath
        $script:ProjectMode = 'composable'
    }

    if (-not $isJoin) {
        if (-not $Client) { Stop-Installation '-Client is required for a new project install' }
        if ($script:ProjectMode -eq 'legacy' -and -not $Prefix) { Stop-Installation '-Prefix is required for a legacy profile install' }
        $rendered = Join-Path $script:TemporaryRoot 'AGENTS.rendered.md'
        if ($script:ProjectMode -eq 'legacy') {
            Expand-LegacyTemplate (Get-SourceFile 'templates/AGENTS.md') $rendered $Client $script:EffectiveProfile $Prefix
        }
        else {
            Expand-ComposableTemplate (Get-SourceFile 'templates/AGENTS-composable.md') $rendered $Client $script:CanonicalProjectTypes $script:CanonicalTechnologies $Prefix
        }
        Install-File $rendered 'AGENTS.md'
    }
    else {
        Write-Info ' = AGENTS.md (join mode)'
    }

    $manifest = $script:Manifest
    $expectedPaths = [Collections.Generic.List[string]]::new()
    $expectedPaths.Add('AGENTS.md')
    foreach ($root in Get-SelectedSkillRoots project) {
        foreach ($row in $manifest | Where-Object {
            @('skill', 'skill-resource').Contains($_.Type) -and
            (Test-ConsumerMatch $_.Consumers 'project:skills') -and
            (Test-PlatformMatch $_.Platforms)
        }) {
            $expectedPaths.Add((Join-Path $root $row.Path.Substring('skills/'.Length).Replace('/', [IO.Path]::DirectorySeparatorChar)))
        }
    }
    if ($script:SelectedTools.Contains('claude')) { $expectedPaths.Add('.claude/settings.json'); $expectedPaths.Add('CLAUDE.md') }
    if ($script:SelectedTools.Contains('gemini')) { $expectedPaths.Add('GEMINI.md') }
    Remove-ObsoleteOwnedArtifacts -ExpectedPaths $expectedPaths.ToArray()
    foreach ($root in Get-SelectedSkillRoots project) {
        Remove-ObsoleteSkillFiles -Manifest $manifest -Root $root
        foreach ($row in $manifest | Where-Object {
            @('skill', 'skill-resource').Contains($_.Type) -and
            (Test-ConsumerMatch $_.Consumers 'project:skills') -and
            (Test-PlatformMatch $_.Platforms)
        }) {
            $relative = $row.Path.Substring('skills/'.Length).Replace('/', [IO.Path]::DirectorySeparatorChar)
            Install-File (Get-SourceFile $row.Path) (Join-Path $root $relative)
        }
    }

    foreach ($tool in $script:SelectedTools) {
        switch ($tool) {
            'claude' {
                if ($script:ProjectMode -eq 'legacy') {
                    $settingsSource = Get-SourceFile "settings/claude/settings-$($script:EffectiveProfile).json"
                }
                else {
                    $settingsSource = Join-Path $script:TemporaryRoot 'settings.composed.json'
                    New-ClaudeSettings (Get-SourceFile 'settings/claude/technology-permissions.tsv') $settingsSource $script:CanonicalTechnologies
                }
                Install-File $settingsSource '.claude/settings.json'
                Install-File (Get-SourceFile 'CLAUDE.md') 'CLAUDE.md'
                Remove-LegacyProjectArtifacts claude
            }
            'codex' { Remove-LegacyProjectArtifacts codex; Write-Info ' = AGENTS.md (Codex native)' }
            'gemini' { Remove-LegacyProjectArtifacts gemini; Install-File (Get-SourceFile 'GEMINI.md') 'GEMINI.md' }
            'cursor' { Remove-LegacyProjectArtifacts cursor; Write-Info ' = AGENTS.md (Cursor native)' }
            'copilot' { Remove-LegacyProjectArtifacts copilot; Write-Info ' = AGENTS.md (Copilot native)' }
        }
    }

    if (-not (Test-Path -LiteralPath 'docs/adr' -PathType Container)) {
        [System.IO.Directory]::CreateDirectory((Join-Path $current 'docs/adr')) | Out-Null
        Set-OwnershipRecord -Path (Join-Path $current 'docs/adr') -Kind directory -Proof 'empty-only'
    }
    Add-GitIgnoreLine '.claude/settings.local.json'
    Add-GitIgnoreLine 'CLAUDE.local.md'
    Add-GitIgnoreLine '.mindflayer-managed.tsv'
    Write-Info "Configured project for: $($script:SelectedTools -join ' ')"
}

try {
    if ($Help) {
        @'
Usage: install.ps1 (-Global | -Project) -Tools TOOL[,TOOL...] [OPTIONS]

Options:
  -Global                 Install user-level artifacts
  -Project                Install artifacts in the current repository
  -Tools LIST             claude,codex,gemini,cursor,copilot
  -ProjectTypes LIST      infrastructure,data-platform,data-engineering
  -Technologies LIST      Comma-separated technology catalog identifiers
  -Profile NAME           Deprecated: terraform, databricks, fabric
  -Client NAME            Client name for a new project install
  -Prefix PREFIX          Resource prefix for a new project install
  -Force                  Back up and replace existing artifacts
  -Help                   Show this help

Requirements:
  Windows 10/11 with PowerShell 7.4+, NTFS directory-junction support for
  global skill discovery, and write access to the selected user or project
  paths. See docs/system-requirements.md for capability-specific requirements.
'@ | Write-Output
        exit 0
    }
    if ($Global -eq $Project) { Stop-Installation 'specify exactly one of -Global or -Project' }
    if (-not $IsWindows -and -not $Local) {
        Stop-Installation 'PowerShell installation is supported only on Windows; -Local is reserved for internal portable tests'
    }
    if (-not $Tools) { Stop-Installation '-Tools is required in non-interactive operation' }
    foreach ($rawTool in $Tools.Split(',')) {
        $tool = ($rawTool -replace '\s', '')
        if (-not $tool) { Stop-Installation '-Tools contains an empty value' }
        if (-not $script:KnownTools.Contains($tool)) {
            Stop-Installation "unknown tool '$tool'; expected one of: $($script:KnownTools -join ',')"
        }
        if ($script:SelectedTools.Contains($tool)) { Stop-Installation "duplicate tool '$tool'" }
        $script:SelectedTools += $tool
    }
    $manifestPath = Join-Path $PSScriptRoot 'manifest.tsv'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        Stop-Installation "bundle manifest not found: $manifestPath"
    }
    $script:Manifest = @(Read-Manifest -Path $manifestPath)
    Assert-ManifestSources -Manifest $script:Manifest

    [System.IO.Directory]::CreateDirectory($script:TemporaryRoot) | Out-Null
    if ($Global) { Install-GlobalToolkit } else { Install-ProjectToolkit }
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
finally {
    if (Test-Path -LiteralPath $script:TemporaryRoot) {
        Remove-Item -LiteralPath $script:TemporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
