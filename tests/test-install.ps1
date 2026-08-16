#Requires -Version 7.4

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$AllTools = 'claude,codex,gemini,cursor,copilot'
$PassCount = 0
$FailCount = 0
$SkipCount = 0
$TestRoot = Join-Path ([IO.Path]::GetTempPath()) "Project Mindflayer PowerShell tests $([guid]::NewGuid().ToString('N'))"

function Assert-True {
    param(
        [Parameter(Mandatory)]
        [bool]$Condition,

        [Parameter(Mandatory)]
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-Equal {
    param(
        [AllowNull()]
        [object]$Actual,

        [AllowNull()]
        [object]$Expected,

        [Parameter(Mandatory)]
        [string]$Message
    )

    if ($Actual -ne $Expected) {
        throw "$Message. Expected '$Expected', got '$Actual'."
    }
}

function Assert-PathExists {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Message
    )

    Assert-True -Condition (Test-Path -LiteralPath $Path) -Message "$Message. Missing: $Path"
}

function Assert-PathNotExists {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Message
    )

    Assert-True -Condition (-not (Test-Path -LiteralPath $Path)) -Message "$Message. Unexpected path: $Path"
}

function Assert-TextContains {
    param(
        [Parameter(Mandatory)]
        [string]$Text,

        [Parameter(Mandatory)]
        [string]$Expected,

        [Parameter(Mandatory)]
        [string]$Message
    )

    Assert-True -Condition $Text.Contains($Expected, [StringComparison]::Ordinal) -Message "$Message. Missing text: $Expected"
}

function Invoke-Test {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [scriptblock]$Test
    )

    try {
        & $Test
        $script:PassCount++
        Write-Host "PASS $Name"
    }
    catch {
        $script:FailCount++
        Write-Host "FAIL $Name" -ForegroundColor Red
        Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Write-Skip {
    param([Parameter(Mandatory)][string]$Message)

    $script:SkipCount++
    Write-Host "SKIP $Message" -ForegroundColor Yellow
}

function New-TestContext {
    param([Parameter(Mandatory)][string]$Name)

    $contextRoot = Join-Path $TestRoot $Name
    $homePath = Join-Path $contextRoot 'user home'
    $projectPath = Join-Path $contextRoot 'project with spaces'
    New-Item -ItemType Directory -Path $homePath, $projectPath -Force | Out-Null

    [pscustomobject]@{
        Home = $homePath
        Project = $projectPath
        Root = $contextRoot
    }
}

function Invoke-PowerShellFile {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [string[]]$Arguments = @(),

        [Parameter(Mandatory)]
        [string]$WorkingDirectory,

        [Parameter(Mandatory)]
        [string]$HomePath,

        [hashtable]$Environment = @{}
    )

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = (Get-Process -Id $PID).Path
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    $startInfo.WorkingDirectory = $WorkingDirectory
    foreach ($argument in @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $FilePath)) {
        $startInfo.ArgumentList.Add($argument)
    }
    foreach ($argument in $Arguments) {
        $startInfo.ArgumentList.Add($argument)
    }

    $startInfo.Environment['HOME'] = $HomePath
    $startInfo.Environment['USERPROFILE'] = $HomePath
    if ($IsWindows) {
        $homeRoot = [IO.Path]::GetPathRoot($HomePath)
        $startInfo.Environment['HOMEDRIVE'] = $homeRoot.TrimEnd([IO.Path]::DirectorySeparatorChar)
        $startInfo.Environment['HOMEPATH'] = $HomePath.Substring($homeRoot.Length - 1)
    }
    foreach ($name in $Environment.Keys) {
        $startInfo.Environment[[string]$name] = [string]$Environment[$name]
    }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    Assert-True -Condition $process.Start() -Message "Failed to start $FilePath"
    $standardOutputTask = $process.StandardOutput.ReadToEndAsync()
    $standardErrorTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()

    [pscustomobject]@{
        ExitCode = $process.ExitCode
        StandardOutput = $standardOutputTask.GetAwaiter().GetResult()
        StandardError = $standardErrorTask.GetAwaiter().GetResult()
    }
}

function Invoke-BashInstaller {
    param(
        [string[]]$Arguments,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][string]$HomePath
    )

    $bashCommand = Get-Command bash -ErrorAction Stop
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $bashCommand.Source
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.ArgumentList.Add((Join-Path $Root 'install.sh'))
    foreach ($argument in $Arguments) {
        $startInfo.ArgumentList.Add($argument)
    }
    $startInfo.Environment['HOME'] = $HomePath

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    Assert-True -Condition $process.Start() -Message 'Failed to start Bash installer'
    $standardOutputTask = $process.StandardOutput.ReadToEndAsync()
    $standardErrorTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()

    [pscustomobject]@{
        ExitCode = $process.ExitCode
        StandardOutput = $standardOutputTask.GetAwaiter().GetResult()
        StandardError = $standardErrorTask.GetAwaiter().GetResult()
    }
}

function Get-NormalizedOwnershipInventory {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [switch]$CommonOnly
    )

    $ownershipPath = Join-Path $ProjectPath '.mindflayer-managed.tsv'
    $commonSkillPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    if ($CommonOnly) {
        foreach ($row in Get-ManifestRows | Where-Object {
                @('skill', 'skill-resource').Contains($_.Type) -and
                $_.Consumers.Split(',').Contains('project:skills') -and
                $_.Platforms -eq 'linux,macos,windows'
            }) {
            [void]$commonSkillPaths.Add($row.Path.Substring('skills/'.Length))
        }
    }
    $rows = foreach ($line in [IO.File]::ReadAllLines($ownershipPath, [Text.Encoding]::UTF8)) {
        if (-not $line) { continue }
        $fields = $line.Split("`t", 3)
        $ownedPath = $fields[0].Replace('\', '/')
        if ([IO.Path]::IsPathRooted($fields[0])) {
            $ownedPath = '<project-path>'
        }
        if ($CommonOnly -and $ownedPath -match '^(?:\.agents|\.claude)/skills/(.+)$' -and -not $commonSkillPaths.Contains($Matches[1])) {
            continue
        }
        $proof = if ($fields[1] -eq 'file') { '<file-proof>' } else { $fields[2] }
        "$ownedPath`t$($fields[1])`t$proof"
    }
    return (@($rows | Sort-Object) -join "`n")
}

function Invoke-Installer {
    param(
        [string[]]$Arguments,
        [string]$WorkingDirectory,
        [string]$HomePath
    )

    Invoke-PowerShellFile -FilePath (Join-Path $Root 'install.ps1') -Arguments $Arguments -WorkingDirectory $WorkingDirectory -HomePath $HomePath
}

function Invoke-Uninstaller {
    param(
        [string[]]$Arguments,
        [string]$WorkingDirectory,
        [string]$HomePath
    )

    Invoke-PowerShellFile -FilePath (Join-Path $Root 'tools/uninstall.ps1') -Arguments $Arguments -WorkingDirectory $WorkingDirectory -HomePath $HomePath
}

function Assert-Success {
    param(
        [Parameter(Mandatory)]
        [object]$Result,

        [Parameter(Mandatory)]
        [string]$Message
    )

    if ($Result.ExitCode -ne 0) {
        throw "$Message failed with exit code $($Result.ExitCode). stdout: $($Result.StandardOutput) stderr: $($Result.StandardError)"
    }
}

function Assert-Failure {
    param(
        [Parameter(Mandatory)]
        [object]$Result,

        [Parameter(Mandatory)]
        [string]$Message
    )

    Assert-True -Condition ($Result.ExitCode -ne 0) -Message "$Message unexpectedly succeeded"
}

function Get-ManifestRows {
    $rows = foreach ($line in [IO.File]::ReadAllLines((Join-Path $Root 'manifest.tsv'), [Text.Encoding]::UTF8)) {
        if (-not $line -or $line.StartsWith('#', [StringComparison]::Ordinal)) {
            continue
        }
        $fields = $line.Split("`t")
        if ($fields.Count -ne 6) {
            throw "Incomplete manifest row: $line"
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
    return @($rows)
}

function Test-PlatformMatch {
    param(
        [Parameter(Mandatory)]
        [object]$Row,

        [Parameter(Mandatory)]
        [ValidateSet('linux', 'macos', 'windows')]
        [string]$Platform
    )

    return $Row.Platforms.Split(',').Contains($Platform)
}

function Assert-ProjectSkillInventory {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [ValidateSet('linux', 'macos', 'windows')]
        [string]$Platform,

        [Parameter(Mandatory)]
        [string[]]$SkillRoots
    )

    $skillRows = Get-ManifestRows | Where-Object {
        @('skill', 'skill-resource').Contains($_.Type) -and
        $_.Consumers.Split(',').Contains('project:skills')
    }
    foreach ($skillRoot in $SkillRoots) {
        foreach ($row in $skillRows) {
            $relativePath = $row.Path.Substring('skills/'.Length).Replace('/', [IO.Path]::DirectorySeparatorChar)
            $installedPath = Join-Path $ProjectPath (Join-Path $skillRoot $relativePath)
            if (Test-PlatformMatch -Row $row -Platform $Platform) {
                Assert-PathExists -Path $installedPath -Message "$Platform project skill artifact $($row.Path)"
            }
            else {
                Assert-PathNotExists -Path $installedPath -Message "Non-$Platform project skill artifact $($row.Path)"
            }
        }
    }
}

function Assert-ProjectCommonSkillInventory {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string[]]$SkillRoots
    )

    $commonRows = Get-ManifestRows | Where-Object {
        @('skill', 'skill-resource').Contains($_.Type) -and
        $_.Consumers.Split(',').Contains('project:skills') -and
        $_.Platforms -eq 'linux,macos,windows'
    }
    foreach ($skillRoot in $SkillRoots) {
        foreach ($row in $commonRows) {
            $relativePath = $row.Path.Substring('skills/'.Length).Replace('/', [IO.Path]::DirectorySeparatorChar)
            Assert-PathExists -Path (Join-Path $ProjectPath (Join-Path $skillRoot $relativePath)) -Message "Common project skill artifact $($row.Path)"
        }
    }
}

function Test-IsGlobalManifestRow {
    param([Parameter(Mandatory)][object]$Row)

    foreach ($consumer in $Row.Consumers.Split(',')) {
        if ($consumer -eq 'global' -or $consumer.StartsWith('global:', [StringComparison]::Ordinal)) {
            return $true
        }
    }
    return $false
}

function Get-ExpectedGlobalPath {
    param(
        [Parameter(Mandatory)]
        [string]$HomePath,

        [Parameter(Mandatory)]
        [string]$ManifestPath
    )

    $toolkitHome = Join-Path $HomePath '.ai-toolkit'
    $nativePath = $ManifestPath.Replace('/', [IO.Path]::DirectorySeparatorChar)
    switch -Regex ($ManifestPath) {
        '^install\.(sh|ps1)$' { return Join-Path $toolkitHome $nativePath }
        '^(README\.md|how-to-guide\.md|LICENSE)$' { return Join-Path (Join-Path $toolkitHome 'docs') $nativePath }
        '^global/AGENTS\.md$' { return Join-Path $toolkitHome 'AGENTS.md' }
        '^(CLAUDE\.md|GEMINI\.md)$' { return Join-Path (Join-Path $toolkitHome 'templates') $nativePath }
        '^templates/' { return Join-Path $toolkitHome $nativePath }
        '^(config|docs|skills)/' { return Join-Path $toolkitHome $nativePath }
        '^tools/' { return Join-Path $toolkitHome ([IO.Path]::GetFileName($nativePath)) }
        '^(stores\.yml|manifest\.tsv)$' { return Join-Path $toolkitHome $nativePath }
        '^settings/claude/' { return Join-Path (Join-Path $toolkitHome 'templates/settings') ([IO.Path]::GetFileName($nativePath)) }
        '^settings/codex/' { return Join-Path (Join-Path $toolkitHome 'templates/codex') ([IO.Path]::GetFileName($nativePath)) }
        '^settings/gemini/' { return Join-Path (Join-Path $toolkitHome 'templates/gemini') ([IO.Path]::GetFileName($nativePath)) }
        default { throw "No expected global destination for $ManifestPath" }
    }
}

function Get-CanonicalPath {
    param([Parameter(Mandatory)][string]$Path)

    [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).Path).TrimEnd([IO.Path]::DirectorySeparatorChar)
}

function Assert-JunctionTarget {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$ExpectedTarget
    )

    $item = Get-Item -LiteralPath $Path -Force
    $isReparsePoint = ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
    Assert-True -Condition $isReparsePoint -Message "$Path is not a reparse point"
    Assert-Equal -Actual $item.LinkType -Expected 'Junction' -Message "$Path is not an NTFS junction"
    Assert-Equal -Actual (Get-CanonicalPath ([string]$item.Target)) -Expected (Get-CanonicalPath $ExpectedTarget) -Message "$Path has the wrong junction target"
}

New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null

try {
    Invoke-Test -Name 'PowerShell 7.4 syntax for required scripts' -Test {
        $requiredScripts = @(
            'install.ps1',
            'tools/check-update.ps1',
            'tools/check-stores.ps1',
            'tools/check-template-update.ps1',
            'tools/check-skills-update.ps1',
            'tools/skill-lifecycle.ps1',
            'tools/sync-global.ps1',
            'tools/sync-skills.ps1',
            'tools/uninstall.ps1',
            'tests/test-install.ps1'
        )
        foreach ($relativePath in $requiredScripts) {
            $scriptPath = Join-Path $Root $relativePath
            Assert-PathExists -Path $scriptPath -Message 'Required PowerShell script exists'
            $parseErrors = $null
            [void][Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$parseErrors)
            Assert-Equal -Actual $parseErrors.Count -Expected 0 -Message "PowerShell syntax errors in $relativePath"
            $firstLine = [IO.File]::ReadLines($scriptPath) | Select-Object -First 1
            Assert-Equal -Actual $firstLine.ToLowerInvariant() -Expected '#requires -version 7.4' -Message "PowerShell minimum version in $relativePath"
        }
    }

    Invoke-Test -Name 'manifest is complete and platform scoped' -Test {
        $manifestRows = Get-ManifestRows
        Assert-True -Condition ($manifestRows.Count -gt 40) -Message 'Manifest should declare more than 40 artifacts'
        Assert-Equal -Actual @($manifestRows.Path | Sort-Object -Unique).Count -Expected $manifestRows.Count -Message 'Manifest paths must be unique'
        Assert-Equal -Actual @($manifestRows | Where-Object Type -eq 'skill').Count -Expected 11 -Message 'Public skill count'
        foreach ($row in $manifestRows) {
            Assert-True -Condition ([bool]$row.Type) -Message "Manifest type for $($row.Path)"
            Assert-True -Condition ([bool]$row.Version) -Message "Manifest version for $($row.Path)"
            Assert-True -Condition ([bool]$row.Consumers) -Message "Manifest consumers for $($row.Path)"
            Assert-True -Condition ([bool]$row.Ownership) -Message "Manifest ownership for $($row.Path)"
            Assert-True -Condition ([bool]$row.Platforms) -Message "Manifest platforms for $($row.Path)"
            $platforms = $row.Platforms.Split(',')
            Assert-Equal -Actual @($platforms | Sort-Object -Unique).Count -Expected $platforms.Count -Message "Unique manifest platforms for $($row.Path)"
            foreach ($platform in $platforms) {
                Assert-True -Condition (@('linux', 'macos', 'windows').Contains($platform)) -Message "Valid manifest platform '$platform' for $($row.Path)"
            }
            Assert-PathExists -Path (Join-Path $Root $row.Path) -Message "Manifest artifact $($row.Path) exists"
        }
        foreach ($artifact in @(
                'install.ps1',
                'tools/check-update.ps1',
                'tools/check-stores.ps1',
                'tools/check-template-update.ps1',
                'tools/check-skills-update.ps1',
                'tools/skill-lifecycle.ps1',
                'tools/sync-global.ps1',
                'tools/sync-skills.ps1',
                'tools/uninstall.ps1'
            )) {
            Assert-Equal -Actual @($manifestRows | Where-Object Path -eq $artifact).Count -Expected 1 -Message "Manifest entry count for $artifact"
        }
        $installerVersion = ($manifestRows | Where-Object Path -eq 'install.ps1').Version
        Assert-True -Condition ([bool]$installerVersion) -Message 'PowerShell installer lifecycle version'
        Assert-TextContains -Text ([IO.File]::ReadAllText((Join-Path $Root 'install.ps1'))) -Expected "`$script:Version = '$installerVersion'" -Message 'Installer version matches manifest'
        foreach ($row in $manifestRows | Where-Object Path -Like '*.ps1') {
            Assert-Equal -Actual $row.Platforms -Expected 'windows' -Message "PowerShell artifact platforms for $($row.Path)"
        }
        foreach ($row in $manifestRows | Where-Object Path -Like '*.sh') {
            Assert-Equal -Actual $row.Platforms -Expected 'linux,macos' -Message "Bash artifact platforms for $($row.Path)"
        }
        Assert-Equal -Actual ($manifestRows | Where-Object Path -eq 'skills/release-notes/scripts/make_outlook_draft.applescript').Platforms -Expected 'macos' -Message 'AppleScript platform'
        Assert-Equal -Actual ($manifestRows | Where-Object Path -eq 'skills/release-notes/scripts/make_email_draft.py').Platforms -Expected 'linux,windows' -Message 'Portable email generator platforms'
        Assert-Equal -Actual @($manifestRows | Where-Object { $_.Path.StartsWith('tests/', [StringComparison]::Ordinal) -or $_.Path -match '/test_[^/]*\.py$' }).Count -Expected 0 -Message 'Repository test modules must not be distributed'
    }

    Invoke-Test -Name 'public installer help is portable and complete' -Test {
        $context = New-TestContext -Name 'portable help'
        $result = Invoke-Installer -Arguments @('-Help') -WorkingDirectory $context.Project -HomePath $context.Home
        Assert-Success -Result $result -Message 'Installer help'
        $helpText = $result.StandardOutput + $result.StandardError
        foreach ($parameter in @('-Global', '-Project', '-Tools', '-ProjectTypes', '-Technologies', '-Profile', '-Client', '-Prefix', '-Force')) {
            Assert-TextContains -Text $helpText -Expected $parameter -Message 'Public help parameter'
        }
        Assert-True -Condition (-not $helpText.Contains('-Local', [StringComparison]::Ordinal)) -Message 'Internal -Local parameter leaked into help'
        Assert-TextContains -Text $helpText -Expected 'PowerShell 7.4' -Message 'PowerShell minimum in installer help'
    }

    Invoke-Test -Name 'portable project install produces canonical output' -Test {
        $context = New-TestContext -Name 'portable project'
        $result = Invoke-Installer -Arguments @(
            '-Project', '-Tools', $AllTools,
            '-ProjectTypes', 'infrastructure,data-engineering',
            '-Technologies', 'terraform,python,sql',
            '-Client', 'Client', '-Local'
        ) -WorkingDirectory $context.Project -HomePath $context.Home
        Assert-Success -Result $result -Message 'Portable project install'
        $agentsPath = Join-Path $context.Project 'AGENTS.md'
        Assert-PathExists -Path $agentsPath -Message 'Canonical project guidance'
        $agentsText = [IO.File]::ReadAllText($agentsPath)
        Assert-TextContains -Text $agentsText -Expected '- **project types:** infrastructure, data-engineering' -Message 'Canonical project types'
        Assert-TextContains -Text $agentsText -Expected '- **technologies:** terraform, python, sql' -Message 'Canonical technologies'
        Assert-PathExists -Path (Join-Path $context.Project 'CLAUDE.md') -Message 'Claude compatibility shim'
        Assert-PathExists -Path (Join-Path $context.Project 'GEMINI.md') -Message 'Gemini compatibility shim'
        Assert-PathExists -Path (Join-Path $context.Project '.claude/settings.json') -Message 'Claude composed settings'
        Assert-ProjectCommonSkillInventory -ProjectPath $context.Project -SkillRoots @('.claude/skills', '.agents/skills')
        Assert-ProjectSkillInventory -ProjectPath $context.Project -Platform windows -SkillRoots @('.claude/skills', '.agents/skills')
        Assert-PathExists -Path (Join-Path $context.Project '.agents/skills/release-notes/scripts/make_email_draft.py') -Message 'PowerShell project email draft generator'
        Assert-PathNotExists -Path (Join-Path $context.Project '.agents/skills/release-notes/scripts/make_outlook_draft.applescript') -Message 'AppleScript excluded from PowerShell project'
        foreach ($testModule in @('test_email_draft.py', 'test_remote.py', 'test_tasks.py')) {
            Assert-PathNotExists -Path (Join-Path $context.Project ".agents/skills/release-notes/scripts/$testModule") -Message "Repository test module $testModule excluded from portable project"
        }
        Assert-PathNotExists -Path (Join-Path $context.Project 'codex.md') -Message 'Legacy Codex shim'
        Assert-PathNotExists -Path (Join-Path $context.Project '.cursor/rules/project.md') -Message 'Legacy Cursor shim'
        Assert-PathNotExists -Path (Join-Path $context.Project '.github/copilot-instructions.md') -Message 'Legacy Copilot shim'

        if ($null -ne (Get-Command bash -ErrorAction SilentlyContinue)) {
            $bashContext = New-TestContext -Name 'portable Bash parity'
            $bashResult = Invoke-BashInstaller -Arguments @(
                '--project', '--tools', $AllTools,
                '--project-types', 'infrastructure,data-engineering',
                '--technologies', 'terraform,python,sql',
                '--client', 'Client', '--local'
            ) -WorkingDirectory $bashContext.Project -HomePath $bashContext.Home
            Assert-Success -Result $bashResult -Message 'Portable Bash parity install'
            foreach ($relativePath in @(
                'AGENTS.md',
                'CLAUDE.md',
                'GEMINI.md',
                '.claude/settings.json',
                '.gitignore'
            )) {
                $powerShellPath = Join-Path $context.Project $relativePath
                $bashPath = Join-Path $bashContext.Project $relativePath
                Assert-PathExists -Path $powerShellPath -Message "PowerShell parity artifact $relativePath"
                Assert-PathExists -Path $bashPath -Message "Bash parity artifact $relativePath"
                $powerShellText = [IO.File]::ReadAllText($powerShellPath).Replace("`r`n", "`n")
                $bashText = [IO.File]::ReadAllText($bashPath).Replace("`r`n", "`n")
                Assert-Equal -Actual $powerShellText -Expected $bashText -Message "Bash and PowerShell differ for $relativePath"
            }
            Assert-Equal `
                -Actual (Get-NormalizedOwnershipInventory -ProjectPath $context.Project -CommonOnly) `
                -Expected (Get-NormalizedOwnershipInventory -ProjectPath $bashContext.Project -CommonOnly) `
                -Message 'Bash and PowerShell common ownership semantics differ'
        }
    }

    Invoke-Test -Name 'store registry parser matches canonical list schema without network' -Test {
        $context = New-TestContext -Name 'portable store parser'
        $result = Invoke-PowerShellFile `
            -FilePath (Join-Path $Root 'tools/check-stores.ps1') `
            -Arguments @('-File', (Join-Path $Root 'stores.yml'), '-ParseOnly') `
            -WorkingDirectory $context.Project `
            -HomePath $context.Home
        Assert-Success -Result $result -Message 'Canonical store registry parse'
        Assert-TextContains -Text $result.StandardOutput -Expected "everything-claude-code`t" -Message 'First canonical store'
        Assert-TextContains -Text $result.StandardOutput -Expected "power-bi-agentic-development`t" -Message 'Second canonical store'
        Assert-TextContains -Text $result.StandardOutput -Expected "`treleases`tv" -Message 'Canonical type and known_version'

        $invalidStores = Join-Path $context.Root 'invalid-stores.yml'
        [IO.File]::WriteAllText($invalidStores, "stores:`n  - id: broken`n    repository: owner/repo`n    known: v1`n", [Text.UTF8Encoding]::new($false))
        $invalid = Invoke-PowerShellFile `
            -FilePath (Join-Path $Root 'tools/check-stores.ps1') `
            -Arguments @('-File', $invalidStores, '-ParseOnly') `
            -WorkingDirectory $context.Project `
            -HomePath $context.Home
        Assert-Failure -Result $invalid -Message 'Legacy store registry keys rejected'
    }

    Invoke-Test -Name 'template checker matches Bash environment and exit contract' -Test {
        $context = New-TestContext -Name 'portable template checker'
        $plainAgents = Join-Path $context.Project 'AGENTS.md'
        [IO.File]::WriteAllText($plainAgents, "# User guidance`n", [Text.UTF8Encoding]::new($false))
        $plain = Invoke-PowerShellFile `
            -FilePath (Join-Path $Root 'tools/check-template-update.ps1') `
            -WorkingDirectory $context.Project `
            -HomePath $context.Home `
            -Environment @{ MINDFlAYER_HOME = $Root }
        Assert-Success -Result $plain -Message 'Non-template AGENTS.md is not an update error'
        Assert-TextContains -Text $plain.StandardOutput -Expected 'not toolkit-template based' -Message 'Non-template status'

        Copy-Item -LiteralPath (Join-Path $Root 'templates/AGENTS.md') -Destination $plainAgents -Force
        $current = Invoke-PowerShellFile `
            -FilePath (Join-Path $Root 'tools/check-template-update.ps1') `
            -WorkingDirectory $context.Project `
            -HomePath $context.Home `
            -Environment @{ MINDFlAYER_HOME = $Root }
        Assert-Success -Result $current -Message 'Current template schema'
        Assert-TextContains -Text $current.StandardOutput -Expected 'Installed schema:' -Message 'Bash-compatible installed label'
        Assert-TextContains -Text $current.StandardOutput -Expected 'Current schema:' -Message 'Bash-compatible current label'
    }

    Invoke-Test -Name 'manifest validation fails before target writes' -Test {
        $context = New-TestContext -Name 'portable manifest validation'
        $bundle = Join-Path $context.Root 'invalid bundle'
        New-Item -ItemType Directory -Path $bundle -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $Root 'install.ps1') -Destination (Join-Path $bundle 'install.ps1')
        [IO.File]::WriteAllText(
            (Join-Path $bundle 'manifest.tsv'),
            "../outside.txt`tdocument`t1.0.0`tproject`tmanaged-file`twindows`n",
            [Text.UTF8Encoding]::new($false)
        )
        $result = Invoke-PowerShellFile `
            -FilePath (Join-Path $bundle 'install.ps1') `
            -Arguments @('-Project', '-Tools', 'codex', '-ProjectTypes', 'infrastructure', '-Technologies', 'python', '-Client', 'Client', '-Local') `
            -WorkingDirectory $context.Project `
            -HomePath $context.Home
        Assert-Failure -Result $result -Message 'Unsafe manifest path'
        Assert-TextContains -Text $result.StandardError -Expected 'unsafe path' -Message 'Manifest path validation error'
        Assert-PathNotExists -Path (Join-Path $context.Project 'AGENTS.md') -Message 'Manifest failure wrote project guidance'
        Assert-PathNotExists -Path (Join-Path $context.Project '.mindflayer-managed.tsv') -Message 'Manifest failure wrote ownership state'
    }

    if (-not $IsWindows) {
        Invoke-Test -Name 'PowerShell public mutation entrypoints fail early off Windows' -Test {
            $context = New-TestContext -Name 'portable host guard'
            $install = Invoke-Installer `
                -Arguments @('-Project', '-Tools', 'codex', '-ProjectTypes', 'infrastructure', '-Technologies', 'python', '-Client', 'Client') `
                -WorkingDirectory $context.Project `
                -HomePath $context.Home
            Assert-Failure -Result $install -Message 'Public installer host guard'
            Assert-PathNotExists -Path (Join-Path $context.Project 'AGENTS.md') -Message 'Host guard ran before project mutation'

            $lifecycle = Invoke-PowerShellFile `
                -FilePath (Join-Path $Root 'tools/skill-lifecycle.ps1') `
                -Arguments @('-Mode', 'Check') `
                -WorkingDirectory $context.Project `
                -HomePath $context.Home
            Assert-Failure -Result $lifecycle -Message 'Public lifecycle host guard'

            $uninstall = Invoke-Uninstaller -Arguments @('-Project') -WorkingDirectory $context.Project -HomePath $context.Home
            Assert-Failure -Result $uninstall -Message 'Public uninstall host guard'
        }

        Invoke-Test -Name 'portable uninstall rejects ownership path escape' -Test {
            $context = New-TestContext -Name 'portable uninstall confinement'
            $outside = Join-Path $context.Root 'outside.txt'
            [IO.File]::WriteAllText($outside, "keep`n", [Text.UTF8Encoding]::new($false))
            $state = Join-Path $context.Project '.mindflayer-managed.tsv'
            [IO.File]::WriteAllText($state, "$outside`tfile`tinvalid`n", [Text.UTF8Encoding]::new($false))
            $result = Invoke-Uninstaller -Arguments @('-Project', '-Confirm', '-Local') -WorkingDirectory $context.Project -HomePath $context.Home
            Assert-Failure -Result $result -Message 'Escaping ownership path'
            Assert-PathExists -Path $outside -Message 'Escaping ownership entry deleted outside file'

            Remove-Item -LiteralPath $state -Force
            $realState = Join-Path $context.Root 'real-state.tsv'
            [IO.File]::WriteAllText($realState, "AGENTS.md`tfile`tinvalid`n", [Text.UTF8Encoding]::new($false))
            New-Item -ItemType SymbolicLink -Path $state -Target $realState | Out-Null
            $linkedState = Invoke-Uninstaller -Arguments @('-Project', '-Confirm', '-Local') -WorkingDirectory $context.Project -HomePath $context.Home
            Assert-Failure -Result $linkedState -Message 'Symlink ownership state'
            Assert-TextContains -Text $linkedState.StandardError -Expected 'reparse point' -Message 'Symlink ownership state error'
        }
    }

    if (-not $IsWindows) {
        Write-Skip -Message 'native Windows installer, NTFS junction, lifecycle, and uninstall tests require Windows'
    }
    else {
        Invoke-Test -Name 'installer argument validation' -Test {
            $context = New-TestContext -Name 'argument validation'
            foreach ($arguments in @(
                    @('-Global', '-Project', '-Tools', 'codex', '-Local'),
                    @('-Global', '-Tools', '', '-Local'),
                    @('-Global', '-Tools', 'unknown', '-Local'),
                    @('-Project', '-Tools', 'codex', '-Local'),
                    @('-Project', '-Tools', 'codex', '-Profile', 'terraform', '-ProjectTypes', 'infrastructure', '-Technologies', 'terraform', '-Local')
                )) {
                $result = Invoke-Installer -Arguments $arguments -WorkingDirectory $context.Project -HomePath $context.Home
                Assert-Failure -Result $result -Message "Invalid installer arguments: $($arguments -join ' ')"
            }
        }

        Invoke-Test -Name 'project compatibility migration preserves unowned artifacts' -Test {
            $context = New-TestContext -Name 'migration safety'
            $legacyCodex = Join-Path $context.Project 'codex.md'
            $legacyCursor = Join-Path $context.Project '.cursor/rules/project.md'
            New-Item -ItemType Directory -Path (Split-Path -Parent $legacyCursor) -Force | Out-Null
            [IO.File]::WriteAllText($legacyCodex, "user-owned Codex guidance`n", [Text.UTF8Encoding]::new($false))
            [IO.File]::WriteAllText($legacyCursor, "user-owned Cursor guidance`n", [Text.UTF8Encoding]::new($false))

            $result = Invoke-Installer -Arguments @(
                '-Project', '-Tools', $AllTools,
                '-ProjectTypes', 'infrastructure', '-Technologies', 'python',
                '-Client', 'Client', '-Local'
            ) -WorkingDirectory $context.Project -HomePath $context.Home
            Assert-Success -Result $result -Message 'Project compatibility migration'
            Assert-Equal -Actual ([IO.File]::ReadAllText($legacyCodex)) -Expected "user-owned Codex guidance`n" -Message 'Unowned legacy Codex guidance preserved'
            Assert-Equal -Actual ([IO.File]::ReadAllText($legacyCursor)) -Expected "user-owned Cursor guidance`n" -Message 'Unowned legacy Cursor guidance preserved'
        }

        Invoke-Test -Name 'global install covers complete manifest inventory and five consumers' -Test {
            $context = New-TestContext -Name 'global inventory'
            $result = Invoke-Installer -Arguments @('-Global', '-Tools', $AllTools, '-Local') -WorkingDirectory $context.Project -HomePath $context.Home
            Assert-Success -Result $result -Message 'Global all-consumer install'
            $manifestRows = Get-ManifestRows
            $expectedVersion = ($manifestRows | Where-Object Path -eq 'install.ps1').Version
            Assert-Equal -Actual ([IO.File]::ReadAllText((Join-Path $context.Home '.ai-toolkit/version')).Trim()) -Expected $expectedVersion -Message 'Installed toolkit version'
            foreach ($row in $manifestRows | Where-Object { (Test-IsGlobalManifestRow $_) -and (Test-PlatformMatch -Row $_ -Platform windows) }) {
                Assert-PathExists -Path (Get-ExpectedGlobalPath -HomePath $context.Home -ManifestPath $row.Path) -Message "Installed global manifest artifact $($row.Path)"
            }
            foreach ($row in $manifestRows | Where-Object { (Test-IsGlobalManifestRow $_) -and -not (Test-PlatformMatch -Row $_ -Platform windows) }) {
                Assert-PathNotExists -Path (Get-ExpectedGlobalPath -HomePath $context.Home -ManifestPath $row.Path) -Message "Non-Windows global manifest artifact $($row.Path)"
            }
            Assert-PathNotExists -Path (Join-Path $context.Home '.ai-toolkit/install.sh') -Message 'Bash installer excluded from Windows install'
            foreach ($relativePath in @('.claude/CLAUDE.md', '.codex/AGENTS.md', '.gemini/GEMINI.md', '.cursor/rules.md', '.copilot/copilot-instructions.md')) {
                Assert-PathExists -Path (Join-Path $context.Home $relativePath) -Message 'Global consumer artifact'
            }
            foreach ($skillRoot in @('.claude/skills', '.agents/skills', '.copilot/skills')) {
                $junction = Join-Path $context.Home (Join-Path $skillRoot 'adr')
                Assert-JunctionTarget -Path $junction -ExpectedTarget (Join-Path $context.Home '.ai-toolkit/skills/adr')
            }
        }

        Invoke-Test -Name 'force replacement backs up user content' -Test {
            $context = New-TestContext -Name 'force backup'
            $codexDirectory = Join-Path $context.Home '.codex'
            $instructions = Join-Path $codexDirectory 'AGENTS.md'
            New-Item -ItemType Directory -Path $codexDirectory -Force | Out-Null
            [IO.File]::WriteAllText($instructions, "user-owned instructions`n", [Text.UTF8Encoding]::new($false))

            $preserve = Invoke-Installer -Arguments @('-Global', '-Tools', 'codex', '-Local') -WorkingDirectory $context.Project -HomePath $context.Home
            Assert-Success -Result $preserve -Message 'Non-force global install'
            Assert-Equal -Actual ([IO.File]::ReadAllText($instructions)) -Expected "user-owned instructions`n" -Message 'Existing instructions preserved without force'

            $replace = Invoke-Installer -Arguments @('-Global', '-Tools', 'codex', '-Force', '-Local') -WorkingDirectory $context.Project -HomePath $context.Home
            Assert-Success -Result $replace -Message 'Forced global install'
            Assert-True -Condition (([IO.File]::ReadAllText($instructions)) -ne "user-owned instructions`n") -Message 'Forced install did not replace instructions'
            $backups = @(Get-ChildItem -LiteralPath $codexDirectory -Filter 'AGENTS.md.bak.*' -Force)
            Assert-True -Condition ($backups.Count -ge 1) -Message 'Forced install did not create a backup'
            Assert-Equal -Actual ([IO.File]::ReadAllText($backups[0].FullName)) -Expected "user-owned instructions`n" -Message 'Backup content'
        }

        Invoke-Test -Name 'skill lifecycle detects drift ignores caches and repairs with backup' -Test {
            $context = New-TestContext -Name 'skill lifecycle'
            $install = Invoke-Installer -Arguments @(
                '-Project', '-Tools', 'claude,codex,copilot',
                '-ProjectTypes', 'infrastructure', '-Technologies', 'python',
                '-Client', 'Client', '-Local'
            ) -WorkingDirectory $context.Project -HomePath $context.Home
            Assert-Success -Result $install -Message 'Lifecycle fixture install'
            $environment = @{ MINDFLAYER_HOME = $Root }
            $checkScript = Join-Path $Root 'tools/check-skills-update.ps1'
            $syncScript = Join-Path $Root 'tools/sync-skills.ps1'
            $current = Invoke-PowerShellFile -FilePath $checkScript -WorkingDirectory $context.Project -HomePath $context.Home -Environment $environment
            Assert-Success -Result $current -Message 'Current skill check'
            Assert-ProjectSkillInventory -ProjectPath $context.Project -Platform windows -SkillRoots @('.claude/skills', '.agents/skills')
            Assert-PathExists -Path (Join-Path $context.Project '.agents/skills/release-notes/scripts/make_email_draft.py') -Message 'Windows email draft generator'
            Assert-PathNotExists -Path (Join-Path $context.Project '.agents/skills/release-notes/scripts/make_outlook_draft.applescript') -Message 'macOS AppleScript excluded from Windows project'
            foreach ($testModule in @('test_email_draft.py', 'test_remote.py', 'test_tasks.py')) {
                Assert-PathNotExists -Path (Join-Path $context.Project ".agents/skills/release-notes/scripts/$testModule") -Message "Repository test module $testModule excluded from Windows project"
            }

            $cacheDirectory = Join-Path $context.Project '.agents/skills/release-notes/scripts/__pycache__'
            New-Item -ItemType Directory -Path $cacheDirectory -Force | Out-Null
            [IO.File]::WriteAllBytes((Join-Path $cacheDirectory 'fixture.pyc'), [byte[]](1, 2, 3))
            $cacheCheck = Invoke-PowerShellFile -FilePath $checkScript -WorkingDirectory $context.Project -HomePath $context.Home -Environment $environment
            Assert-Success -Result $cacheCheck -Message 'Unmanifested cache ignored by drift check'

            $target = Join-Path $context.Project '.agents/skills/adr/SKILL.md'
            [IO.File]::AppendAllText($target, "`nlocal drift`n", [Text.UTF8Encoding]::new($false))
            $driftedHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
            $drift = Invoke-PowerShellFile -FilePath $checkScript -WorkingDirectory $context.Project -HomePath $context.Home -Environment $environment
            Assert-Failure -Result $drift -Message 'Drifted skill check'
            Assert-TextContains -Text ($drift.StandardOutput + $drift.StandardError) -Expected 'DRIFTED' -Message 'Drift status'

            $dryRun = Invoke-PowerShellFile -FilePath $syncScript -Arguments @('-DryRun', '-Force') -WorkingDirectory $context.Project -HomePath $context.Home -Environment $environment
            Assert-Success -Result $dryRun -Message 'Forced lifecycle dry run'
            Assert-Equal -Actual (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -Expected $driftedHash -Message 'Dry run changed target'

            $preserve = Invoke-PowerShellFile -FilePath $syncScript -WorkingDirectory $context.Project -HomePath $context.Home -Environment $environment
            Assert-Success -Result $preserve -Message 'Non-force lifecycle sync'
            Assert-Equal -Actual (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -Expected $driftedHash -Message 'Non-force sync changed drifted target'

            $repair = Invoke-PowerShellFile -FilePath $syncScript -Arguments @('-Force') -WorkingDirectory $context.Project -HomePath $context.Home -Environment $environment
            Assert-Success -Result $repair -Message 'Forced lifecycle sync'
            Assert-Equal -Actual (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -Expected (Get-FileHash -LiteralPath (Join-Path $Root 'skills/adr/SKILL.md') -Algorithm SHA256).Hash -Message 'Forced sync did not repair target'
            Assert-True -Condition (@(Get-ChildItem -LiteralPath (Split-Path -Parent (Split-Path -Parent $target)) -Filter 'adr.bak.*' -Force).Count -ge 1) -Message 'Forced sync did not create a recoverable backup'
            Assert-PathExists -Path (Join-Path $cacheDirectory 'fixture.pyc') -Message 'Lifecycle sync removed an unmanifested cache'
        }

        Invoke-Test -Name 'skill lifecycle validates modes and managed roots' -Test {
            $context = New-TestContext -Name 'lifecycle validation'
            $install = Invoke-Installer -Arguments @(
                '-Project', '-Tools', 'codex', '-ProjectTypes', 'infrastructure',
                '-Technologies', 'python', '-Client', 'Client', '-Local'
            ) -WorkingDirectory $context.Project -HomePath $context.Home
            Assert-Success -Result $install -Message 'Lifecycle validation fixture'
            $environment = @{ MINDFLAYER_HOME = $Root }
            $invalidMode = Invoke-PowerShellFile -FilePath (Join-Path $Root 'tools/skill-lifecycle.ps1') -Arguments @('-Mode', 'Check', '-DryRun') -WorkingDirectory $context.Project -HomePath $context.Home -Environment $environment
            Assert-Failure -Result $invalidMode -Message 'Check mode with DryRun'

        $ownershipPath = Join-Path $context.Project '.mindflayer-managed.tsv'
        $ownedSourceRecord = [IO.File]::ReadAllLines($ownershipPath, [Text.Encoding]::UTF8) |
            Where-Object { $_ -match '[\\/]skills[\\/]adr[\\/]SKILL\.md\tfile\t' } |
            Select-Object -First 1
        $ownedSourceFields = $ownedSourceRecord.Split("`t", 3)
        $obsoletePath = Join-Path $context.Project '.agents/skills/adr/obsolete.md'
        Copy-Item -LiteralPath (Join-Path $context.Project '.agents/skills/adr/SKILL.md') -Destination $obsoletePath
        [IO.File]::AppendAllText($ownershipPath, ".agents/skills/adr/obsolete.md`tfile`t$($ownedSourceFields[2])`n", [Text.UTF8Encoding]::new($false))
        $obsoleteCheck = Invoke-PowerShellFile -FilePath (Join-Path $Root 'tools/check-skills-update.ps1') -WorkingDirectory $context.Project -HomePath $context.Home -Environment $environment
        Assert-Failure -Result $obsoleteCheck -Message 'Obsolete owned skill file check'
        Assert-TextContains -Text $obsoleteCheck.StandardOutput -Expected 'OBSOLETE' -Message 'Obsolete skill status'
        $obsoleteSync = Invoke-PowerShellFile -FilePath (Join-Path $Root 'tools/sync-skills.ps1') -WorkingDirectory $context.Project -HomePath $context.Home -Environment $environment
        Assert-Success -Result $obsoleteSync -Message 'Obsolete owned skill file sync'
        Assert-PathNotExists -Path $obsoletePath -Message 'Verified obsolete owned skill file preserved'

        Copy-Item -LiteralPath (Join-Path $context.Project '.agents/skills/adr/SKILL.md') -Destination $obsoletePath
        [IO.File]::AppendAllText($obsoletePath, "modified`n", [Text.UTF8Encoding]::new($false))
        [IO.File]::AppendAllText($ownershipPath, ".agents/skills/adr/obsolete.md`tfile`t$($ownedSourceFields[2])`n", [Text.UTF8Encoding]::new($false))
        $modifiedSync = Invoke-PowerShellFile -FilePath (Join-Path $Root 'tools/sync-skills.ps1') -WorkingDirectory $context.Project -HomePath $context.Home -Environment $environment
        Assert-Success -Result $modifiedSync -Message 'Modified obsolete skill sync'
        Assert-PathExists -Path $obsoletePath -Message 'Modified obsolete skill file removed'
            [IO.File]::AppendAllText($ownershipPath, "../outside/skills/adr/SKILL.md`tfile`tinvalid`n", [Text.UTF8Encoding]::new($false))
            $unsafeCheck = Invoke-PowerShellFile -FilePath (Join-Path $Root 'tools/check-skills-update.ps1') -WorkingDirectory $context.Project -HomePath $context.Home -Environment $environment
            Assert-Failure -Result $unsafeCheck -Message 'Unsafe managed skill root check'
            $unsafeSync = Invoke-PowerShellFile -FilePath (Join-Path $Root 'tools/sync-skills.ps1') -Arguments @('-Force') -WorkingDirectory $context.Project -HomePath $context.Home -Environment $environment
            Assert-Failure -Result $unsafeSync -Message 'Unsafe managed skill root sync'
        }

        Invoke-Test -Name 'template store update and synchronization wrappers' -Test {
            $context = New-TestContext -Name 'helper wrappers'
            Copy-Item -LiteralPath (Join-Path $Root 'templates/AGENTS.md') -Destination (Join-Path $context.Project 'AGENTS.md')
        $templateCheck = Invoke-PowerShellFile -FilePath (Join-Path $Root 'tools/check-template-update.ps1') -WorkingDirectory $context.Project -HomePath $context.Home -Environment @{ MINDFlAYER_HOME = $Root }
            Assert-Success -Result $templateCheck -Message 'Current template check'
        Assert-TextContains -Text $templateCheck.StandardOutput -Expected 'Current schema:' -Message 'Current template status'

        $storesCheck = Invoke-PowerShellFile `
            -FilePath (Join-Path $Root 'tools/check-stores.ps1') `
            -Arguments @('-File', (Join-Path $Root 'stores.yml'), '-ParseOnly') `
            -WorkingDirectory $context.Project `
            -HomePath $context.Home
            Assert-Success -Result $storesCheck -Message 'Store registry wrapper'
            Assert-TextContains -Text $storesCheck.StandardOutput -Expected 'Registry:' -Message 'Store registry source'

            $syncGlobal = Invoke-PowerShellFile -FilePath (Join-Path $Root 'tools/sync-global.ps1') -WorkingDirectory $context.Project -HomePath $context.Home
            Assert-Success -Result $syncGlobal -Message 'Global sync guidance'
            Assert-TextContains -Text $syncGlobal.StandardOutput -Expected '-Tools <explicit-list> -Force' -Message 'Global sync explicit replacement guidance'
        }

        Invoke-Test -Name 'update wrapper reports current and available versions' -Test {
            $context = New-TestContext -Name 'update wrapper'
            $toolkitHome = Join-Path $context.Home '.ai-toolkit'
            New-Item -ItemType Directory -Path $toolkitHome -Force | Out-Null
            [IO.File]::WriteAllText((Join-Path $toolkitHome 'version'), "3.6.0`n", [Text.UTF8Encoding]::new($false))
            $updateScript = (Join-Path $Root 'tools/check-update.ps1').Replace("'", "''")
        foreach ($latest in @('v3.6.0', 'v9.0.0')) {
                $wrapper = Join-Path $context.Root "check update $($latest.TrimStart('v')).ps1"
                $wrapperText = @"
function Invoke-RestMethod {
    param([uri]`$Uri, [hashtable]`$Headers)
    [pscustomobject]@{ tag_name = '$latest' }
}
& '$updateScript'
exit `$LASTEXITCODE
"@
                [IO.File]::WriteAllText($wrapper, $wrapperText, [Text.UTF8Encoding]::new($false))
                $result = Invoke-PowerShellFile -FilePath $wrapper -WorkingDirectory $context.Project -HomePath $context.Home
                Assert-Success -Result $result -Message "Update wrapper for $latest"
            Assert-TextContains -Text $result.StandardOutput -Expected 'Installed: 3.6.0' -Message 'Installed version output'
                Assert-TextContains -Text $result.StandardOutput -Expected "Latest: $($latest.TrimStart('v'))" -Message 'Latest version output'
            }
        }

        Invoke-Test -Name 'uninstall dry run preserves and confirmed uninstall removes owned artifacts' -Test {
            $context = New-TestContext -Name 'uninstall'
            $install = Invoke-Installer -Arguments @('-Global', '-Tools', $AllTools, '-Local') -WorkingDirectory $context.Project -HomePath $context.Home
            Assert-Success -Result $install -Message 'Uninstall fixture install'
            $userFile = Join-Path $context.Home '.codex/user-owned.txt'
            [IO.File]::WriteAllText($userFile, "keep`n", [Text.UTF8Encoding]::new($false))

            $dryRun = Invoke-Uninstaller -Arguments @('-Global') -WorkingDirectory $context.Project -HomePath $context.Home
            Assert-Success -Result $dryRun -Message 'Global uninstall dry run'
            Assert-PathExists -Path (Join-Path $context.Home '.codex/AGENTS.md') -Message 'Dry run preserved owned consumer file'
            Assert-PathExists -Path (Join-Path $context.Home '.agents/skills/adr') -Message 'Dry run preserved owned junction'

            $confirmed = Invoke-Uninstaller -Arguments @('-Global', '-Confirm') -WorkingDirectory $context.Project -HomePath $context.Home
            Assert-Success -Result $confirmed -Message 'Confirmed global uninstall'
            Assert-PathNotExists -Path (Join-Path $context.Home '.codex/AGENTS.md') -Message 'Confirmed uninstall removed owned consumer file'
            Assert-PathNotExists -Path (Join-Path $context.Home '.agents/skills/adr') -Message 'Confirmed uninstall removed owned junction'
            Assert-PathExists -Path $userFile -Message 'Confirmed uninstall preserved unowned file'
        }
    }
}
finally {
    if (Test-Path -LiteralPath $TestRoot) {
        Remove-Item -LiteralPath $TestRoot -Recurse -Force
    }
}

Write-Host ''
Write-Host "PASS: $PassCount FAIL: $FailCount SKIP: $SkipCount"
if ($FailCount -ne 0) {
    exit 1
}
