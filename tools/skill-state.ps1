#requires -Version 7.4
# Shared project-skill state for install.ps1 and skill-lifecycle.ps1. Dot-source
# it; it defines functions only. Callers set $script:UseColor and write the
# returned or emitted lines to their output.

Set-StrictMode -Version Latest

function Format-Color {
    param([Parameter(Mandatory)][string]$Code, [AllowEmptyString()][string]$Text)
    if ($script:UseColor) { return "`e[$($Code)m$Text`e[0m" }
    return $Text
}

function ConvertTo-LfText {
    param([AllowEmptyString()][string]$Text)
    return $Text.Replace("`r`n", "`n").Replace("`r", "`n")
}

function Get-NormalizedText {
    param([Parameter(Mandatory)][string]$Path)
    return ConvertTo-LfText ([IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8))
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

function Test-IsReparsePoint {
    param([AllowNull()][object]$Item)
    return $null -ne $Item -and ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
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

# Writes the unified diff from the local file (---) to the release (+++).
function Write-Diff {
    param(
        [Parameter(Mandatory)][string]$LocalPath,
        [Parameter(Mandatory)][string]$ReleasePath,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$LocalDescription,
        [Parameter(Mandatory)][string]$ReleaseDescription
    )
    $item = Get-Item -LiteralPath $LocalPath -Force -ErrorAction SilentlyContinue
    $localText = if ($null -ne $item -and -not $item.PSIsContainer -and -not (Test-IsReparsePoint $item)) {
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

function Test-SkillsLinePresent {
    param([Parameter(Mandatory)][string]$Path)
    return (Test-Path -LiteralPath $Path -PathType Leaf) -and
        [regex]::IsMatch((Get-NormalizedText $Path), '(?m)^\s*- \*\*skills:\*\*')
}

# Reads the selection declared in AGENTS.md ("- **skills:** a, b" or "none").
# Without the line every available skill is selected. Invalid is true when the
# line names unknown skills or has no value; an invalid line must never cause
# skills to be removed, because a typo would uninstall the skill it meant.
function Read-SkillSelection {
    param([Parameter(Mandatory)][string]$Path, [AllowEmptyCollection()][string[]]$Available)
    $result = [pscustomobject]@{ Selection = @($Available); Invalid = $false; Problem = '' }
    if (-not (Test-SkillsLinePresent $Path)) { return $result }
    $match = [regex]::Match((Get-NormalizedText $Path), '(?m)^\s*- \*\*skills:\*\*(.*)$')
    $value = $match.Groups[1].Value -replace '\s', ''
    $result.Selection = @()
    if (-not $value) {
        $result.Invalid = $true
        $result.Problem = 'the skills line has no value; write skill names or none'
        [Console]::Error.WriteLine('! AGENTS.md has an empty skills line; no skills are removed until it lists skill names or none')
        return $result
    }
    if ($value -eq 'none') { return $result }
    $unknown = [Collections.Generic.List[string]]::new()
    $kept = [Collections.Generic.List[string]]::new()
    foreach ($token in $value.Split(',')) {
        if (-not $token) { continue }
        if (@($Available) -contains $token) { $kept.Add($token) }
        else {
            $unknown.Add($token)
            [Console]::Error.WriteLine("! AGENTS.md selects skill '$token', which this release does not provide; ignoring it")
        }
    }
    if ($unknown.Count -gt 0) {
        $result.Invalid = $true
        $result.Problem = "unknown skills: $($unknown -join ', ')"
    }
    $result.Selection = @(@($Available) | Where-Object { $kept.Contains($_) })
    return $result
}

# Returns AGENTS.md text (LF) with the skills line set, or removed when every
# skill is selected so default projects keep the unchanged template.
function Set-SkillsLineText {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [AllowEmptyCollection()][string[]]$Selection,
        [AllowEmptyCollection()][string[]]$Available
    )
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
        if ($anchor -lt 0) { throw 'error: could not record the skill selection in AGENTS.md' }
        $lines.Insert($anchor + 1, $line)
    }
    $result = $lines -join "`n"
    if ($trailing) { $result += "`n" }
    return $result
}

# Replaces a file's content through a sibling temporary file and a rename, so an
# interruption never leaves it truncated. A file that used CRLF keeps CRLF.
# Reparse points are refused because writing through one could change a file
# outside the project.
function Set-TextFileAtomically {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowEmptyString()][string]$Content)
    $fullPath = [IO.Path]::GetFullPath($Path)
    $item = Get-Item -LiteralPath $fullPath -Force -ErrorAction SilentlyContinue
    if (Test-IsReparsePoint $item) {
        throw "error: $Path is a link; replace it with a regular file before changing the skill selection"
    }
    $text = ConvertTo-LfText $Content
    if ($null -ne $item -and [IO.File]::ReadAllText($fullPath, [Text.Encoding]::UTF8).Contains("`r`n")) {
        $text = $text.Replace("`n", "`r`n")
    }
    $temporary = Join-Path (Split-Path -Parent $fullPath) (".{0}.{1}.tmp" -f [IO.Path]::GetFileName($fullPath), [guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllText($temporary, $text, [Text.UTF8Encoding]::new($false))
        if ($null -ne $item) { [IO.File]::Replace($temporary, $fullPath, [NullString]::Value) } else { [IO.File]::Move($temporary, $fullPath) }
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}

# State of one manifest file in a skill root:
#   new       missing locally
#   current   identical to the release (line endings ignored)
#   update    unchanged since the toolkit installed it; the release differs
#   local     installed by the toolkit, then edited
#   unmanaged exists but was not installed by the toolkit
# Proof is the recorded ownership fingerprint, or $null when not owned.
function Get-SkillFileState {
    param([Parameter(Mandatory)][string]$Destination, [Parameter(Mandatory)][string]$Source, [AllowNull()][string]$Proof)
    $item = Get-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) { return 'new' }
    if ($item.PSIsContainer -or (Test-IsReparsePoint $item)) {
        if ($Proof) { return 'local' } else { return 'unmanaged' }
    }
    if ((Get-NormalizedText $Source) -ceq (Get-NormalizedText $Destination)) { return 'current' }
    if (-not $Proof) { return 'unmanaged' }
    if ((Get-CksumProof $Destination) -eq $Proof) { return 'update' }
    return 'local'
}

function Get-StateRank {
    param([string]$State)
    switch ($State) { 'not-installed' { 0 } 'current' { 1 } 'update' { 2 } 'local' { 3 } 'unmanaged' { 4 } default { 0 } }
}

# A skill directory replaced by a link, junction, or file is a local change.
# Nothing is ever written through it.
function Test-SkillDirectoryReplaced {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Name)
    $item = Get-Item -LiteralPath (Join-Path $Root $Name) -Force -ErrorAction SilentlyContinue
    return $null -ne $item -and (-not $item.PSIsContainer -or (Test-IsReparsePoint $item))
}

# True when an ownership record lies below a project skill directory that a
# link or file replaced. Such records are left alone: resolving them would
# follow the link, and nothing below it is ever written or removed.
function Test-RecordUnderReplacedSkillDirectory {
    param([Parameter(Mandatory)][string]$RecordedPath)
    $normalized = $RecordedPath.Replace('\', '/')
    if ([IO.Path]::IsPathRooted($RecordedPath) -or $normalized.Split('/') -contains '..') { return $false }
    if ($normalized -notmatch '^(.*/skills)/([^/]+)/.+$') { return $false }
    return Test-SkillDirectoryReplaced -Root $Matches[1] -Name $Matches[2]
}

# Aggregated state of a skill in one root, including owned files the release no
# longer declares: not-installed | current | update | local | unmanaged.
# Records are ownership records with FullPath, Kind, and Proof.
function Get-SkillRootState {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Files,
        [Parameter(Mandatory)][string]$SourceRoot,
        [AllowEmptyCollection()][object[]]$Records = @()
    )
    $skillDirectory = Join-Path $Root $Name
    if ($null -eq (Get-Item -LiteralPath $skillDirectory -Force -ErrorAction SilentlyContinue)) { return 'not-installed' }
    if (Test-SkillDirectoryReplaced -Root $Root -Name $Name) { return 'local' }
    $worst = 'current'
    $existing = $false
    $expected = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($relative in $Files) {
        $destination = [IO.Path]::GetFullPath((Join-Path $skillDirectory ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))))
        [void]$expected.Add($destination)
        $proof = (@($Records) | Where-Object { $_.Kind -eq 'file' -and $_.FullPath.Equals($destination, [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
        $state = Get-SkillFileState -Destination $destination -Source (Join-Path (Join-Path $SourceRoot $Name) $relative) -Proof $(if ($proof) { $proof.Proof } else { $null })
        if ($state -eq 'new') { $state = 'update' } else { $existing = $true }
        if ((Get-StateRank $state) -gt (Get-StateRank $worst)) { $worst = $state }
    }
    $fullDirectory = [IO.Path]::GetFullPath($skillDirectory).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    foreach ($record in @($Records)) {
        if ($record.Kind -ne 'file' -or -not $record.FullPath.StartsWith($fullDirectory, [StringComparison]::OrdinalIgnoreCase) -or $expected.Contains($record.FullPath)) { continue }
        $item = Get-Item -LiteralPath $record.FullPath -Force -ErrorAction SilentlyContinue
        if ($null -eq $item) { continue }
        $existing = $true
        $state = if (-not $item.PSIsContainer -and -not (Test-IsReparsePoint $item) -and (Get-CksumProof $record.FullPath) -eq $record.Proof) { 'update' } else { 'local' }
        if ((Get-StateRank $state) -gt (Get-StateRank $worst)) { $worst = $state }
    }
    if (-not $existing -and $worst -eq 'update') {
        # The directory exists but holds none of the skill's files.
        if (@(Get-ChildItem -LiteralPath $skillDirectory -Force -ErrorAction SilentlyContinue).Count -gt 0) { return 'unmanaged' }
        return 'not-installed'
    }
    return $worst
}

# Removes directories of a skill that became empty.
function Remove-EmptySkillDirectories {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Name, [AllowEmptyCollection()][string[]]$Files)
    if (Test-SkillDirectoryReplaced -Root $Root -Name $Name) { return }
    $skillDirectory = [IO.Path]::GetFullPath((Join-Path $Root $Name))
    $candidates = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($relative in @($Files)) {
        $directory = Split-Path -Parent ([IO.Path]::GetFullPath((Join-Path $skillDirectory ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar)))))
        while ($directory) {
            [void]$candidates.Add($directory)
            if ($directory.Equals($skillDirectory, [StringComparison]::OrdinalIgnoreCase)) { break }
            if (-not $directory.StartsWith($skillDirectory + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { break }
            $directory = Split-Path -Parent $directory
        }
    }
    foreach ($directory in @($candidates | Sort-Object Length -Descending)) {
        $item = Get-Item -LiteralPath $directory -Force -ErrorAction SilentlyContinue
        if ($null -ne $item -and $item.PSIsContainer -and -not (Test-IsReparsePoint $item) -and
            @(Get-ChildItem -LiteralPath $directory -Force).Count -eq 0) {
            Remove-Item -LiteralPath $directory -Force
        }
    }
}

# Writes the "Migration required" summary for migrations with Kind, Path, and
# Detail. Returns nothing; Test-MigrationUnresolved reports the exit status.
function Write-MigrationSummary {
    param([AllowEmptyCollection()][object[]]$Migrations)
    $all = @($Migrations)
    if ($all.Count -eq 0) { return }
    $kept = @($all | Where-Object Kind -eq 'kept')
    $removal = @($all | Where-Object Kind -eq 'kept-removal')
    $replaced = @($all | Where-Object Kind -eq 'replaced')
    $invalid = @($all | Where-Object Kind -eq 'invalid-selection')
    Write-Output ''
    Write-Output (Format-Color '1;31' 'Migration required')
    if ($invalid.Count -gt 0) {
        Write-Output '  The skills line in AGENTS.md is invalid; no skills were removed:'
        foreach ($entry in $invalid) { Write-Output "    ! $($entry.Path)  ($($entry.Detail))" }
    }
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
    if ($invalid.Count -gt 0) {
        Write-Output '    - Fix the "- **skills:**" line in AGENTS.md: list skill names, or write none.'
        Write-Output '      Then rerun to apply the selection.'
    }
    if ($kept.Count -gt 0) {
        Write-Output "    - Review the diffs above: '-' lines are your version, '+' lines are the release."
        Write-Output '      Move your customizations out of toolkit-managed files (for example into a'
        Write-Output '      project-specific skill), then rerun with -Force to take the release.'
        Write-Output '      -Force saves your version as <file>.bak.<timestamp> before replacing it.'
    }
    if ($removal.Count -gt 0) {
        Write-Output '    - Files kept after their skill was removed stay listed here until you delete them.'
        Write-Output '      Copy anything you still need into your own files, then delete them.'
    }
    if ($replaced.Count -gt 0) {
        Write-Output '    - Re-apply any customizations you still need from the saved .bak files.'
    }
}

function Test-MigrationUnresolved {
    param([AllowEmptyCollection()][object[]]$Migrations)
    return @(@($Migrations) | Where-Object { $_.Kind -in 'kept', 'kept-removal', 'invalid-selection' }).Count -gt 0
}
