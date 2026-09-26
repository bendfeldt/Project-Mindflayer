#requires -Version 7.4

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Force,
    # -Add without names opens a list of available skills; -Add adr,smart-pr adds those skills.
    [switch]$Add,
    [Parameter(ValueFromRemainingArguments)]
    [string[]]$Skills,
    [Parameter(DontShow)]
    [switch]$Local
)

if ($Skills -and -not $Add) {
    [Console]::Error.WriteLine("error: unexpected argument '$($Skills -join ' ')'; use -Add NAME[,NAME] to add skills")
    exit 1
}
$addSkills = (@($Skills) | Where-Object { $_ }) -join ','
& (Join-Path $PSScriptRoot 'skill-lifecycle.ps1') -Mode Sync -DryRun:$DryRun -Force:$Force -Add:$Add -AddSkills $addSkills -Local:$Local
exit $LASTEXITCODE
