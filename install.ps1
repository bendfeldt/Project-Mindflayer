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
    [string[]]$Skills,
    [switch]$Interactive,
    [switch]$SkillsStatus,
    [switch]$Force,
    [switch]$Help,
    [Parameter(DontShow)]
    [switch]$Local
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Version = '3.8.0'
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
$script:SkillCatalog = @()
$script:SkillRoots = @()
$script:SkillStates = @{}
$script:SkillOwned = @{}
$script:SelectedSkills = @()
$script:Migrations = [Collections.Generic.List[object]]::new()
$script:DiffsShown = $false
$script:ExitStatus = 0
$script:ProjectScope = $false
$script:UseColor = (-not [Console]::IsOutputRedirected) -and (-not $env:NO_COLOR) -and ($env:TERM -ne 'dumb')

function Write-Info {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Message)
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
    param([Parameter(Mandatory)][string]$Path, [string]$Reason = 'obsolete')
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
            Write-WarningMessage "preserved $Reason $($record.Path) (modified or type changed)"
            Add-Migration -Kind kept-removal -Path $record.Path -Detail $Reason
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
    Write-Info " - $($record.Path) ($Reason)"
}

# Removes owned files under a skill root that are no longer expected. With a
# selection (project mode), files of unselected skills are removed as
# "deselected"; files the manifest no longer declares are "obsolete".
function Remove-ObsoleteSkillFiles {
    param(
        [Parameter(Mandatory)][object[]]$Manifest,
        [Parameter(Mandatory)][string]$Root,
        [AllowNull()][AllowEmptyCollection()][string[]]$Selection = $null
    )
    $expected = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $declared = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($row in $Manifest) {
        if (-not @('skill', 'skill-resource').Contains($row.Type) -or
            -not (Test-ConsumerMatch $row.Consumers 'project:skills') -or
            -not (Test-PlatformMatch $row.Platforms)) {
            continue
        }
        $relative = $row.Path.Substring('skills/'.Length).Replace('/', [IO.Path]::DirectorySeparatorChar)
        $fullPath = Resolve-ManagedPath -RecordedPath (Join-Path $Root $relative)
        [void]$declared.Add($fullPath)
        $skillName = $row.Path.Split('/')[1]
        if ($null -eq $Selection -or @($Selection) -contains $skillName) { [void]$expected.Add($fullPath) }
    }
    $fullRoot = Resolve-ManagedPath -RecordedPath $Root
    foreach ($record in @(Get-OwnershipRecords)) {
        if ((Test-PathWithinRoot -Path $record.FullPath -Root $fullRoot) -and
            -not $expected.Contains($record.FullPath)) {
            $reason = if ($declared.Contains($record.FullPath)) { 'deselected' } else { 'obsolete' }
            Remove-VerifiedOwnedArtifact $record.Path -Reason $reason
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

# ---------------------------------------------------------------------------
# Project skill selection, status detection, diffs, and migration reporting.
# ---------------------------------------------------------------------------

function Format-Color {
    param([Parameter(Mandatory)][string]$Code, [AllowEmptyString()][string]$Text)
    if ($script:UseColor) { return "`e[$($Code)m$Text`e[0m" }
    return $Text
}

function Format-HostColor {
    param([Parameter(Mandatory)][string]$Code, [AllowEmptyString()][string]$Text)
    if (-not $env:NO_COLOR -and $env:TERM -ne 'dumb') { return "`e[$($Code)m$Text`e[0m" }
    return $Text
}

function Test-InteractiveAvailable {
    return (-not $env:MINDFLAYER_NONINTERACTIVE) -and (-not $env:CI) -and
        (-not [Console]::IsInputRedirected) -and (-not [Console]::IsOutputRedirected)
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
    param(
        [Parameter(Mandatory)][string]$LocalPath,
        [Parameter(Mandatory)][string]$ReleasePath,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$LocalDescription,
        [Parameter(Mandatory)][string]$ReleaseDescription
    )
    $item = Get-ItemIfPresent $LocalPath
    $localText = if ($null -ne $item -and -not $item.PSIsContainer -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
        Get-NormalizedFileText $LocalPath
    }
    else { '' }
    $lines = Get-UnifiedDiff -OldLines (Split-TextLines $localText) -NewLines (Split-TextLines (Get-NormalizedFileText $ReleasePath)) `
        -OldLabel "$Label ($LocalDescription)" -NewLabel "$Label ($ReleaseDescription)"
    foreach ($line in $lines) {
        if ($line.StartsWith('--- ') -or $line.StartsWith('+++ ')) { Write-Info (Format-Color '1' $line) }
        elseif ($line.StartsWith('@@')) { Write-Info (Format-Color '36' $line) }
        elseif ($line.StartsWith('-')) { Write-Info (Format-Color '31' $line) }
        elseif ($line.StartsWith('+')) { Write-Info (Format-Color '32' $line) }
        else { Write-Info $line }
    }
}

function Initialize-SkillCatalog {
    $catalog = [Collections.Generic.List[object]]::new()
    $byName = @{}
    foreach ($row in $script:Manifest) {
        if (-not @('skill', 'skill-resource').Contains($row.Type) -or
            -not (Test-ConsumerMatch $row.Consumers 'project:skills') -or
            -not (Test-PlatformMatch $row.Platforms)) { continue }
        if ($row.Path -notmatch '^skills/([a-z0-9-]+)/(.+)$') { Stop-Installation "unsafe skill name in manifest: $($row.Path)" }
        $name = $Matches[1]
        $relative = $Matches[2]
        if (-not $byName.ContainsKey($name)) {
            $entry = [pscustomobject]@{ Name = $name; Version = ''; Description = ''; Files = [Collections.Generic.List[string]]::new() }
            $byName[$name] = $entry
            $catalog.Add($entry)
        }
        $byName[$name].Files.Add($relative)
        if ($row.Type -eq 'skill') {
            $byName[$name].Version = $row.Version
            $yaml = Join-Path $PSScriptRoot "skills/$name/agents/openai.yaml"
            if (Test-Path -LiteralPath $yaml -PathType Leaf) {
                $match = [regex]::Match((Get-NormalizedFileText $yaml), '(?m)^\s*short_description:\s*"(.*)"\s*$')
                if ($match.Success) { $byName[$name].Description = $match.Groups[1].Value }
            }
        }
    }
    $script:SkillCatalog = @($catalog | Where-Object { $_.Version })
    if ($script:SkillCatalog.Count -eq 0) { Stop-Installation 'the release bundle declares no project skills' }
}

function Get-AllSkillNames { return @($script:SkillCatalog | ForEach-Object Name) }

function Get-SkillEntry {
    param([Parameter(Mandatory)][string]$Name)
    return $script:SkillCatalog | Where-Object Name -eq $Name | Select-Object -First 1
}

function Get-CanonicalSkillList {
    param([AllowEmptyCollection()][string[]]$Names)
    $wanted = @($Names)
    return @(Get-AllSkillNames | Where-Object { $wanted -contains $_ })
}

function Test-AllSkillsSelected {
    param([AllowEmptyCollection()][string[]]$Selection)
    return (@($Selection) -join ',') -ceq ((Get-AllSkillNames) -join ',')
}

function Format-SkillSelection {
    param([AllowEmptyCollection()][string[]]$Selection)
    if (@($Selection).Count -eq 0) { return 'none' }
    return (@($Selection) -join ', ')
}

function Resolve-SkillRequest {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Request)
    $available = Get-AllSkillNames
    $value = $Request -replace '\s', ''
    if ($value -eq 'all') { return , @($available) }
    if ($value -eq 'none') { return , @() }
    if (-not $value) { Stop-Installation '-Skills requires a value: skill names, all, or none' }
    $seen = [Collections.Generic.List[string]]::new()
    foreach ($token in $value.Split(',')) {
        if (-not $token) { Stop-Installation '-Skills contains an empty value' }
        if (@('all', 'none').Contains($token)) { Stop-Installation "-Skills: '$token' cannot be combined with skill names" }
        if (-not $available.Contains($token)) { Stop-Installation "unknown skill '$token'; available skills: $($available -join ', ')" }
        if ($seen.Contains($token)) { Stop-Installation "duplicate skill '$token' in -Skills" }
        $seen.Add($token)
    }
    return , @(Get-CanonicalSkillList $seen.ToArray())
}

function Test-AgentsSkillsLine {
    param([Parameter(Mandatory)][string]$Path)
    return (Test-Path -LiteralPath $Path -PathType Leaf) -and
        [regex]::IsMatch((Get-NormalizedFileText $Path), '(?m)^\s*- \*\*skills:\*\*')
}

function Get-StoredSkillSelection {
    param([Parameter(Mandatory)][string]$Path)
    $match = [regex]::Match((Get-NormalizedFileText $Path), '(?m)^\s*- \*\*skills:\*\*(.*)$')
    $value = $match.Groups[1].Value -replace '\s', ''
    if (-not $value -or $value -eq 'none') { return , @() }
    $available = Get-AllSkillNames
    $kept = foreach ($token in $value.Split(',')) {
        if (-not $token) { continue }
        if ($available.Contains($token)) { $token }
        else { Write-WarningMessage "AGENTS.md selects skill '$token', which this release does not provide; ignoring it" }
    }
    return , @(Get-CanonicalSkillList @($kept))
}

# Returns AGENTS.md text with the skills line set, or removed when every skill
# is selected so default projects keep the unchanged template.
function Set-SkillsLineText {
    param([Parameter(Mandatory)][string]$Text, [AllowEmptyCollection()][string[]]$Selection)
    $remove = Test-AllSkillsSelected $Selection
    $line = '- **skills:** ' + (Format-SkillSelection $Selection)
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
        if ($anchor -lt 0) { Stop-Installation 'could not record the skill selection in AGENTS.md' }
        $lines.Insert($anchor + 1, $line)
    }
    $result = $lines -join "`n"
    if ($trailing) { $result += "`n" }
    return $result
}

function Get-OwnedFileRecord {
    param([Parameter(Mandatory)][string]$Path)
    $fullPath = [IO.Path]::GetFullPath($Path)
    return Get-OwnershipRecords | Where-Object { $_.Kind -eq 'file' -and $_.FullPath.Equals($fullPath, [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
}

# new | current | update (unchanged since install) | local (edited) | unmanaged
function Get-SkillFileState {
    param([Parameter(Mandatory)][string]$Destination, [Parameter(Mandatory)][string]$Source)
    $item = Get-ItemIfPresent $Destination
    if ($null -eq $item) { return 'new' }
    $record = Get-OwnedFileRecord $Destination
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        if ($null -ne $record) { return 'local' } else { return 'unmanaged' }
    }
    if ((Get-NormalizedFileText $Source) -ceq (Get-NormalizedFileText $Destination)) { return 'current' }
    if ($null -eq $record) { return 'unmanaged' }
    if ((Get-CksumProof $Destination) -eq $record.Proof) { return 'update' }
    return 'local'
}

function Get-StateRank {
    param([string]$State)
    switch ($State) { 'not-installed' { 0 } 'current' { 1 } 'update' { 2 } 'local' { 3 } 'unmanaged' { 4 } default { 0 } }
}

function Get-SkillRootState {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][object]$Skill)
    $skillDirectory = Join-Path $Root $Skill.Name
    if ($null -eq (Get-ItemIfPresent $skillDirectory)) { return 'not-installed' }
    $worst = 'current'
    $existing = $false
    $expected = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($relative in $Skill.Files) {
        $destination = Join-Path $skillDirectory ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))
        [void]$expected.Add([IO.Path]::GetFullPath($destination))
        $state = Get-SkillFileState -Destination $destination -Source (Join-Path $PSScriptRoot "skills/$($Skill.Name)/$relative")
        if ($state -eq 'new') { $state = 'update' } else { $existing = $true }
        if ((Get-StateRank $state) -gt (Get-StateRank $worst)) { $worst = $state }
    }
    $fullDirectory = [IO.Path]::GetFullPath($skillDirectory)
    foreach ($record in @(Get-OwnershipRecords)) {
        if ($record.Kind -ne 'file' -or -not (Test-PathWithinRoot -Path $record.FullPath -Root $fullDirectory) -or $expected.Contains($record.FullPath)) { continue }
        $item = Get-ItemIfPresent $record.FullPath
        if ($null -eq $item) { continue }
        $existing = $true
        $state = if (-not $item.PSIsContainer -and (Get-CksumProof $record.FullPath) -eq $record.Proof) { 'update' } else { 'local' }
        if ((Get-StateRank $state) -gt (Get-StateRank $worst)) { $worst = $state }
    }
    if (-not $existing) {
        if (@(Get-ChildItem -LiteralPath $skillDirectory -Force -ErrorAction SilentlyContinue).Count -gt 0) { return 'unmanaged' }
        return 'not-installed'
    }
    return $worst
}

function Update-SkillStates {
    $script:SkillStates = @{}
    $script:SkillOwned = @{}
    foreach ($skill in $script:SkillCatalog) {
        $worst = $null
        $missing = $false
        $owned = $false
        foreach ($root in $script:SkillRoots) {
            $state = Get-SkillRootState -Root $root -Skill $skill
            if ($state -eq 'not-installed') { $missing = $true }
            elseif ($null -eq $worst -or (Get-StateRank $state) -gt (Get-StateRank $worst)) { $worst = $state }
            if ($null -ne (Get-OwnedFileRecord (Join-Path (Join-Path $root $skill.Name) 'SKILL.md'))) { $owned = $true }
        }
        if ($null -eq $worst) { $worst = 'not-installed' }
        elseif ($missing -and $worst -eq 'current') { $worst = 'update' }
        $script:SkillStates[$skill.Name] = $worst
        $script:SkillOwned[$skill.Name] = $owned
    }
}

function Get-StateLabel {
    param([string]$State)
    switch ($State) {
        'not-installed' { 'not installed' } 'current' { 'up to date' } 'update' { 'update available' }
        'local' { 'local changes' } 'unmanaged' { 'not managed' } default { $State }
    }
}

function Get-StateColor {
    param([string]$State)
    switch ($State) { 'current' { '32' } 'update' { '33' } 'local' { '31' } 'unmanaged' { '31' } default { '2' } }
}

function Add-Migration {
    param([string]$Kind, [string]$Path, [string]$Detail)
    if ($script:ProjectScope) {
        $script:Migrations.Add([pscustomobject]@{ Kind = $Kind; Path = $Path; Detail = $Detail })
    }
}

function Write-SkillDiffs {
    param([AllowEmptyCollection()][string[]]$Names)
    foreach ($name in @($Names)) {
        $skill = Get-SkillEntry $name
        foreach ($root in $script:SkillRoots) {
            foreach ($relative in $skill.Files) {
                $destination = Join-Path (Join-Path $root $name) ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))
                $source = Join-Path $PSScriptRoot "skills/$name/$relative"
                $label = "$root/$name/$relative"
                switch (Get-SkillFileState -Destination $destination -Source $source) {
                    'update' { Write-Diff $destination $source $label 'installed' "release $($skill.Version)" }
                    { $_ -in 'local', 'unmanaged' } {
                        Write-Info ("{0} {1}" -f (Format-Color '1;31' 'LOCAL CHANGES - migration required:'), $label)
                        Write-Diff $destination $source $label 'your version' "release $($skill.Version)"
                    }
                }
            }
        }
    }
}

# Interactive multi-select; returns the chosen names in manifest order.
function Read-SkillChoice {
    param([Parameter(Mandatory)][string]$Title, [string[]]$Candidates, [AllowEmptyCollection()][string[]]$Preselected, [switch]$ShowStatus)
    $names = @($Candidates)
    $marks = [bool[]]::new($names.Count)
    for ($i = 0; $i -lt $names.Count; $i++) { $marks[$i] = @($Preselected) -contains $names[$i] }
    while ($true) {
        Write-Host ''
        Write-Host (Format-HostColor '1' $Title)
        if ($ShowStatus) { Write-Host ('         {0,-22} {1,-17} {2,-8} {3}' -f 'Skill', 'Status', 'Release', 'Description') }
        else { Write-Host ('         {0,-22} {1,-8} {2}' -f 'Skill', 'Release', 'Description') }
        for ($i = 0; $i -lt $names.Count; $i++) {
            $skill = Get-SkillEntry $names[$i]
            $mark = if ($marks[$i]) { '[x]' } else { '[ ]' }
            if ($ShowStatus) {
                $state = $script:SkillStates[$names[$i]]
                $status = Format-HostColor (Get-StateColor $state) ('{0,-17}' -f (Get-StateLabel $state))
                Write-Host ('  {0} {1,2} {2,-22} {3} {4,-8} {5}' -f $mark, ($i + 1), $names[$i], $status, $skill.Version, $skill.Description)
            }
            else {
                Write-Host ('  {0} {1,2} {2,-22} {3,-8} {4}' -f $mark, ($i + 1), $names[$i], $skill.Version, $skill.Description)
            }
        }
        Write-Host ''
        Write-Host 'Toggle with numbers or names (e.g. "3 5-7"), a = all, n = none,'
        Write-Host 'Enter = continue, q = cancel without changes.'
        [Console]::Write('> ')
        $inputLine = [Console]::ReadLine()
        if ($null -eq $inputLine) { Stop-Installation 'input closed; nothing was changed' }
        $inputLine = $inputLine.Replace(',', ' ').Trim()
        if (-not $inputLine) { break }
        if (@('q', 'quit', 'cancel').Contains($inputLine.ToLowerInvariant())) { Stop-Installation 'cancelled; nothing was changed' }
        if (@('a', 'all').Contains($inputLine.ToLowerInvariant())) { for ($i = 0; $i -lt $names.Count; $i++) { $marks[$i] = $true }; continue }
        if (@('n', 'none').Contains($inputLine.ToLowerInvariant())) { for ($i = 0; $i -lt $names.Count; $i++) { $marks[$i] = $false }; continue }
        foreach ($token in ($inputLine -split '\s+')) {
            if ($token -match '^(\d+)-(\d+)$') {
                $start = [int]$Matches[1]; $end = [int]$Matches[2]
                if ($start -lt 1 -or $end -gt $names.Count -or $start -gt $end) {
                    Write-Host (Format-HostColor '33' "Ignored '$token': choose numbers from 1 to $($names.Count).")
                    continue
                }
                for ($i = $start - 1; $i -lt $end; $i++) { $marks[$i] = -not $marks[$i] }
            }
            elseif ($token -match '^\d+$') {
                $number = [int]$token
                if ($number -lt 1 -or $number -gt $names.Count) {
                    Write-Host (Format-HostColor '33' "Ignored '$token': choose numbers from 1 to $($names.Count).")
                    continue
                }
                $marks[$number - 1] = -not $marks[$number - 1]
            }
            else {
                $position = [array]::IndexOf($names, $token)
                if ($position -lt 0) {
                    Write-Host (Format-HostColor '33' "Ignored '$token': not a number or skill name in the list.")
                    continue
                }
                $marks[$position] = -not $marks[$position]
            }
        }
    }
    return , @(for ($i = 0; $i -lt $names.Count; $i++) { if ($marks[$i]) { $names[$i] } })
}

function Write-SkillPlan {
    param([AllowEmptyCollection()][string[]]$Selection)
    $lines = [Collections.Generic.List[string]]::new()
    foreach ($skill in $script:SkillCatalog) {
        $name = $skill.Name
        $state = $script:SkillStates[$name]
        $line = $null
        if (@($Selection) -contains $name) {
            switch ($state) {
                'not-installed' { $line = "$(Format-HostColor '32' '+ install ')  $name $($skill.Version)" }
                'update' { $line = "$(Format-HostColor '33' '~ update  ')  $name -> $($skill.Version)" }
                { $_ -in 'local', 'unmanaged' } {
                    $line = if ($Force) { "$(Format-HostColor '31' '! replace ')  $name ($(Get-StateLabel $state); your version is backed up first)" }
                    else { "$(Format-HostColor '31' '! keep    ')  $name ($(Get-StateLabel $state); migration required, -Force replaces)" }
                }
            }
        }
        else {
            switch ($state) {
                'unmanaged' { $line = "$(Format-HostColor '2' '= leave   ')  $name (not installed by the toolkit)" }
                'local' { $line = "$(Format-HostColor '31' '- remove  ')  $name (unchanged files only; edited files are kept)" }
                'not-installed' { }
                default { if ($script:SkillOwned[$name]) { $line = "$(Format-HostColor '31' '- remove  ')  $name" } }
            }
        }
        if ($line) { $lines.Add("  $line") }
    }
    if ($lines.Count -eq 0) { return $false }
    Write-Host 'Planned skill changes:'
    foreach ($line in $lines) { Write-Host $line }
    return $true
}

function Confirm-SkillPlan {
    param([AllowEmptyCollection()][string[]]$Selection)
    $changed = @($script:SkillCatalog | Where-Object {
            (@($Selection) -contains $_.Name) -and @('update', 'local', 'unmanaged').Contains($script:SkillStates[$_.Name])
        } | ForEach-Object Name)
    while ($true) {
        if ($changed.Count -gt 0) { [Console]::Write('Proceed? [Y]es, [n]o, [d]iffs: ') } else { [Console]::Write('Proceed? [Y]es, [n]o: ') }
        $answer = [Console]::ReadLine()
        if ($null -eq $answer) { Stop-Installation 'input closed; nothing was changed' }
        switch -Regex ($answer.Trim()) {
            '^(|y|yes)$' { return }
            '^(n|no|q)$' { Stop-Installation 'cancelled; nothing was changed' }
            '^d$' { if ($changed.Count -gt 0) { Write-SkillDiffs $changed; $script:DiffsShown = $true } }
        }
    }
}

function Resolve-SkillSelection {
    param([bool]$IsJoin, [Parameter(Mandatory)][string]$AgentsPath)
    Initialize-SkillCatalog
    Update-SkillStates
    $current = if ($IsJoin -and (Test-AgentsSkillsLine $AgentsPath)) { Get-StoredSkillSelection $AgentsPath } else { Get-AllSkillNames }
    if ($null -ne $Skills) {
        $script:SelectedSkills = Resolve-SkillRequest ($Skills -join ',')
    }
    elseif ($Interactive -or (Test-InteractiveAvailable)) {
        if ([Console]::IsInputRedirected) { Stop-Installation '-Interactive needs a terminal; use -Skills LIST instead' }
        $script:SelectedSkills = Read-SkillChoice -Title "Choose skills to install in $($script:SkillRoots -join ', ')" `
            -Candidates (Get-AllSkillNames) -Preselected $current -ShowStatus
        if (Write-SkillPlan $script:SelectedSkills) { Confirm-SkillPlan $script:SelectedSkills }
    }
    else {
        $script:SelectedSkills = @($current)
    }
}

# Replaces a file's content through a sibling temporary file and a rename, so an
# interruption never leaves it truncated. Reparse points are refused because
# writing through one could change a file outside the project.
function Set-FileContentAtomically {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowEmptyString()][string]$Content)
    $item = Get-ItemIfPresent $Path
    if ($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        Stop-Installation "$Path is a link; replace it with a regular file before changing the skill selection"
    }
    $temporary = Join-Path (Split-Path -Parent ([IO.Path]::GetFullPath($Path))) (".{0}.{1}.tmp" -f [IO.Path]::GetFileName($Path), [guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllText($temporary, (ConvertTo-LfText $Content), $script:Utf8NoBom)
        if ($null -ne $item) { [IO.File]::Replace($temporary, $Path, [NullString]::Value) } else { [IO.File]::Move($temporary, $Path) }
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}

# Returns the updated AGENTS.md text, or $null when AGENTS.md does not need to
# change. Runs before any write so a link is rejected before the install starts.
function Get-AgentsSelectionUpdate {
    param([Parameter(Mandatory)][string]$AgentsPath)
    if (-not (Test-Path -LiteralPath $AgentsPath -PathType Leaf)) { return $null }
    $text = Get-NormalizedFileText $AgentsPath
    if (-not $text.Contains('<!-- template: AGENTS ')) {
        if (-not (Test-AllSkillsSelected $script:SelectedSkills)) { Write-WarningMessage 'AGENTS.md is not toolkit-managed; the skill selection was not recorded' }
        return $null
    }
    $updated = Set-SkillsLineText -Text $text -Selection $script:SelectedSkills
    if ($updated -ceq $text) { return $null }
    $item = Get-ItemIfPresent $AgentsPath
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        Stop-Installation 'AGENTS.md is a link; replace it with a regular file before changing the skill selection'
    }
    return $updated
}

function Update-AgentsSelection {
    param([Parameter(Mandatory)][string]$AgentsPath)
    $updated = Get-AgentsSelectionUpdate -AgentsPath $AgentsPath
    if ($null -eq $updated) { return }
    $summary = if (Test-AllSkillsSelected $script:SelectedSkills) { 'all' } else { Format-SkillSelection $script:SelectedSkills }
    Write-Info " ~ AGENTS.md (skills: $summary)"
    $rendered = Join-Path $script:TemporaryRoot 'AGENTS.selection.md'
    Write-LfFile -Path $rendered -Content $updated
    Write-Diff $AgentsPath $rendered 'AGENTS.md' 'current' 'updated'
    $record = Get-OwnedFileRecord $AgentsPath
    $wasOwned = $null -ne $record -and (Get-CksumProof $AgentsPath) -eq $record.Proof
    Set-FileContentAtomically -Path $AgentsPath -Content $updated
    if ($wasOwned) { Set-OwnershipRecord -Path $record.Path -Kind file -Proof (Get-CksumProof $AgentsPath) }
}

function Install-SkillFile {
    param([Parameter(Mandatory)][object]$Skill, [Parameter(Mandatory)][string]$Relative, [Parameter(Mandatory)][string]$Root)
    $source = Get-SourceFile "skills/$($Skill.Name)/$Relative"
    $destination = Join-Path (Join-Path $Root $Skill.Name) ($Relative.Replace('/', [IO.Path]::DirectorySeparatorChar))
    [void](Resolve-ManagedPath -RecordedPath $destination)
    $label = "$Root/$($Skill.Name)/$Relative"
    $release = "release $($Skill.Version)"
    switch (Get-SkillFileState -Destination $destination -Source $source) {
        { $_ -in 'new', 'current' } { Install-File $source $destination }
        'update' {
            Write-Info " ~ $destination (update to $($Skill.Name) $($Skill.Version))"
            if (-not $script:DiffsShown) { Write-Diff $destination $source $label 'installed' $release }
            Write-LfFile -Path $destination -Content (Get-NormalizedFileText $source)
            Set-OwnershipRecord -Path $destination -Kind file -Proof (Get-CksumProof $destination)
        }
        { $_ -in 'local', 'unmanaged' } {
            if ($Force) {
                Write-WarningMessage "$destination has local changes; replacing it with $($Skill.Name) $($Skill.Version) (-Force)"
                if (-not $script:DiffsShown) { Write-Diff $destination $source $label 'your version' $release }
                $backup = Get-BackupPath $destination
                Backup-And-RemoveItem $destination
                Write-LfFile -Path $destination -Content (Get-NormalizedFileText $source)
                Set-OwnershipRecord -Path $destination -Kind file -Proof (Get-CksumProof $destination)
                Add-Migration -Kind replaced -Path $destination -Detail $backup
            }
            else {
                Write-WarningMessage "$destination has local changes; kept. LOCAL CHANGES - migration required"
                if (-not $script:DiffsShown) { Write-Diff $destination $source $label 'your version' $release }
                Add-Migration -Kind kept -Path $destination -Detail "$($Skill.Name) $($Skill.Version)"
            }
        }
    }
}

function Remove-EmptySkillDirectories {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][object]$Skill)
    $skillDirectory = [IO.Path]::GetFullPath((Join-Path $Root $Skill.Name))
    $candidates = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($relative in $Skill.Files) {
        $directory = Split-Path -Parent ([IO.Path]::GetFullPath((Join-Path $skillDirectory ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar)))))
        while ($directory -and (Test-PathWithinRoot -Path $directory -Root $skillDirectory)) {
            [void]$candidates.Add($directory)
            if ($directory.Equals($skillDirectory, [StringComparison]::OrdinalIgnoreCase)) { break }
            $directory = Split-Path -Parent $directory
        }
    }
    foreach ($directory in @($candidates | Sort-Object Length -Descending)) {
        $item = Get-ItemIfPresent $directory
        if ($null -ne $item -and $item.PSIsContainer -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -and
            @(Get-ChildItem -LiteralPath $directory -Force).Count -eq 0) {
            Remove-Item -LiteralPath $directory -Force
        }
    }
}

function Write-MigrationSummary {
    if ($script:Migrations.Count -eq 0) { return }
    $kept = @($script:Migrations | Where-Object Kind -eq 'kept')
    $removal = @($script:Migrations | Where-Object Kind -eq 'kept-removal')
    $replaced = @($script:Migrations | Where-Object Kind -eq 'replaced')
    Write-Info ''
    Write-Info (Format-Color '1;31' 'Migration required')
    if ($kept.Count -gt 0) {
        Write-Info "  Kept with local changes, not updated ($($kept.Count)):"
        foreach ($entry in $kept) { Write-Info "    ! $($entry.Path)  (release: $($entry.Detail))" }
    }
    if ($removal.Count -gt 0) {
        Write-Info "  Kept although no longer installed, because they have local changes ($($removal.Count)):"
        foreach ($entry in $removal) { Write-Info "    ! $($entry.Path)  ($($entry.Detail))" }
    }
    if ($replaced.Count -gt 0) {
        Write-Info "  Replaced by the release; your previous version was saved ($($replaced.Count)):"
        foreach ($entry in $replaced) { Write-Info "    ! $($entry.Path)  -> $($entry.Detail)" }
    }
    Write-Info '  Next steps:'
    if ($kept.Count -gt 0) {
        Write-Info "    - Review the diffs above: '-' lines are your version, '+' lines are the release."
        Write-Info '      Move your customizations out of toolkit-managed files (for example into a'
        Write-Info '      project-specific skill), then rerun with -Force to take the release.'
        Write-Info '      -Force saves your version as <file>.bak.<timestamp> before replacing it.'
    }
    if ($removal.Count -gt 0) {
        Write-Info '    - Files kept after their skill was removed stay listed here until you delete them.'
        Write-Info '      Copy anything you still need into your own files, then delete them.'
    }
    if ($replaced.Count -gt 0) {
        Write-Info '    - Re-apply any customizations you still need from the saved .bak files.'
    }
    if ($kept.Count -gt 0 -or $removal.Count -gt 0) { $script:ExitStatus = 2 }
}

function Write-SkillsStatus {
    param([Parameter(Mandatory)][string]$AgentsPath)
    Initialize-SkillCatalog
    Update-SkillStates
    if (Test-AgentsSkillsLine $AgentsPath) {
        $selection = Get-StoredSkillSelection $AgentsPath
        Write-Info "Selected in AGENTS.md: $(Format-SkillSelection $selection)"
    }
    else {
        $selection = Get-AllSkillNames
        if (Test-Path -LiteralPath $AgentsPath -PathType Leaf) { Write-Info 'Selected in AGENTS.md: all skills (no skills line)' }
        else { Write-Info 'No AGENTS.md yet: a new install selects all skills' }
    }
    foreach ($root in $script:SkillRoots) {
        Write-Info ''
        Write-Info (Format-Color '1' $root)
        Write-Info ('      {0,-22} {1,-17} {2}' -f 'Skill', 'Status', 'Release')
        foreach ($skill in $script:SkillCatalog) {
            $state = Get-SkillRootState -Root $root -Skill $skill
            $marker = if (@($selection) -contains $skill.Name) { '[x]' } else { '[ ]' }
            Write-Info ('  {0} {1,-22} {2} {3}' -f $marker, $skill.Name, (Format-Color (Get-StateColor $state) ('{0,-17}' -f (Get-StateLabel $state))), $skill.Version)
        }
    }
    $changed = @($script:SkillCatalog | Where-Object { @('update', 'local', 'unmanaged').Contains($script:SkillStates[$_.Name]) } | ForEach-Object Name)
    Write-Info ''
    if ($changed.Count -gt 0) {
        Write-Info (Format-Color '1' 'Differences (--- installed, +++ release):')
        Write-SkillDiffs $changed
        Write-Info ''
        Write-Info 'Apply release updates by rerunning without -SkillsStatus. Files with local'
        Write-Info 'changes are kept and reported for migration unless -Force is given.'
    }
    else {
        Write-Info 'All installed skills match this release.'
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
    $script:ProjectScope = $true
    Assert-OwnershipFileSafe
    [void](Get-OwnershipRecords)
    $agentsPath = Join-Path $current 'AGENTS.md'
    $script:SkillRoots = @(Get-SelectedSkillRoots project)
    if ($SkillsStatus) {
        if ($script:SkillRoots.Count -eq 0) { Stop-Installation '-SkillsStatus needs a tool with a skill root: claude, codex, or copilot' }
        Write-SkillsStatus -AgentsPath $agentsPath
        return
    }
    if ($script:SkillRoots.Count -eq 0 -and ($null -ne $Skills -or $Interactive)) {
        Stop-Installation 'the selected tools have no project skill root; skills are used by claude, codex, and copilot'
    }
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
    }

    # Every question is asked before the first write, so cancelling changes nothing.
    if ($script:SkillRoots.Count -gt 0) {
        Resolve-SkillSelection -IsJoin $isJoin -AgentsPath $agentsPath
        if ($isJoin) { [void](Get-AgentsSelectionUpdate -AgentsPath $agentsPath) }
    }

    if (-not $isJoin) {
        $rendered = Join-Path $script:TemporaryRoot 'AGENTS.rendered.md'
        if ($script:ProjectMode -eq 'legacy') {
            Expand-LegacyTemplate (Get-SourceFile 'templates/AGENTS.md') $rendered $Client $script:EffectiveProfile $Prefix
        }
        else {
            Expand-ComposableTemplate (Get-SourceFile 'templates/AGENTS-composable.md') $rendered $Client $script:CanonicalProjectTypes $script:CanonicalTechnologies $Prefix
        }
        if ($script:SkillRoots.Count -gt 0) {
            Write-LfFile -Path $rendered -Content (Set-SkillsLineText -Text (Get-NormalizedFileText $rendered) -Selection $script:SelectedSkills)
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
    if ($script:SkillRoots.Count -gt 0) {
        if ($isJoin) { Update-AgentsSelection -AgentsPath $agentsPath }
        foreach ($root in $script:SkillRoots) {
            Remove-ObsoleteSkillFiles -Manifest $manifest -Root $root -Selection $script:SelectedSkills
            foreach ($skill in $script:SkillCatalog | Where-Object { $script:SelectedSkills -notcontains $_.Name }) {
                Remove-EmptySkillDirectories -Root $root -Skill $skill
            }
        }
        foreach ($skill in $script:SkillCatalog | Where-Object { $script:SelectedSkills -contains $_.Name }) {
            foreach ($relative in $skill.Files) {
                foreach ($root in $script:SkillRoots) { Install-SkillFile -Skill $skill -Relative $relative -Root $root }
            }
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
    if ($script:SkillRoots.Count -gt 0) {
        $summary = if (Test-AllSkillsSelected $script:SelectedSkills) { 'all' } else { Format-SkillSelection $script:SelectedSkills }
        Write-Info "Skills: $summary"
    }
    Write-MigrationSummary
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
  -Skills LIST            Skills to install in the project: comma-separated
                          names, all, or none. Omitted: all skills for a new
                          project, the AGENTS.md selection for an existing one.
  -Interactive            Choose skills from an interactive list (project mode).
                          Offered automatically when a terminal is attached.
  -SkillsStatus           Show installed skills, available updates, and diffs,
                          then exit without changing anything (project mode)
  -Force                  Back up and replace existing artifacts
  -Help                   Show this help

Skill updates from a newer release are applied with a diff. Skill files with
local changes are kept, shown as a diff, and listed for migration; the exit
status is then 2. Set MINDFLAYER_NONINTERACTIVE=1 or NO_COLOR=1 to disable the
interactive list or colored output.

Requirements:
  Windows 10/11 with PowerShell 7.4+, NTFS directory-junction support for
  global skill discovery, and write access to the selected user or project
  paths. See docs/system-requirements.md for capability-specific requirements.
'@ | Write-Output
        exit 0
    }
    if ($Global -eq $Project) { Stop-Installation 'specify exactly one of -Global or -Project' }
    if ($Global -and ($null -ne $Skills -or $Interactive -or $SkillsStatus)) {
        Stop-Installation '-Skills, -Interactive, and -SkillsStatus apply to -Project installs only'
    }
    if ($null -ne $Skills -and $Interactive) {
        Stop-Installation 'choose skills either with -Skills or with -Interactive, not both'
    }
    if ($SkillsStatus -and ($null -ne $Skills -or $Interactive -or $Force)) {
        Stop-Installation '-SkillsStatus only reports; it cannot be combined with -Skills, -Interactive, or -Force'
    }
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
    exit $script:ExitStatus
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
