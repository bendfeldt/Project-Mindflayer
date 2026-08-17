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
$script:CosignVersion = '2.4.1'
$script:Repository = 'bendfeldt/Project-Mindflayer'
$script:StagingDirectory = Join-Path ([IO.Path]::GetTempPath()) "project-mindflayer-$([guid]::NewGuid().ToString('N'))"

if (-not $IsWindows -and -not $Local) {
    throw 'PowerShell bootstrap is supported only on Windows'
}

$processorArchitecture = if ($env:PROCESSOR_ARCHITEW6432) {
    $env:PROCESSOR_ARCHITEW6432
}
else {
    $env:PROCESSOR_ARCHITECTURE
}
if ($processorArchitecture -notin @('AMD64', 'ARM64')) {
    throw 'supported Windows architectures are amd64 and arm64'
}

[void](New-Item -ItemType Directory -Path $script:StagingDirectory)
try {
    $cosignCommand = (Get-Command cosign -ErrorAction SilentlyContinue).Source
    if (-not $cosignCommand) {
        # Sigstore does not publish a Windows arm64 v2.4.1 binary; use amd64 through x64 emulation.
        $cosignAsset = 'cosign-windows-amd64.exe'
        $cosignHash = '8d57f8a42a981d27290c4227271fa9f0f62ca6630eb4a21d316bd6b01405b87c'
        $cosignCommand = Join-Path $script:StagingDirectory 'cosign.exe'
        Invoke-WebRequest `
            -Uri "https://github.com/sigstore/cosign/releases/download/v$($script:CosignVersion)/$cosignAsset" `
            -OutFile $cosignCommand
        $actualCosignHash = (Get-FileHash $cosignCommand -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualCosignHash -ne $cosignHash) {
            throw 'Cosign bootstrap checksum verification failed'
        }
    }

    $asset = "project-mindflayer-$($script:Version)-windows.zip"
    $releaseBase = "https://github.com/$($script:Repository)/releases/download/v$($script:Version)"
    $archive = Join-Path $script:StagingDirectory $asset
    $checksum = "$archive.sha256"
    $signatureBundle = "$archive.sigstore.json"

    Invoke-WebRequest -Uri "$releaseBase/$asset" -OutFile $archive
    Invoke-WebRequest -Uri "$releaseBase/$asset.sha256" -OutFile $checksum
    Invoke-WebRequest -Uri "$releaseBase/$asset.sigstore.json" -OutFile $signatureBundle

    $expectedHash = ((Get-Content -LiteralPath $checksum -Raw) -split '\s+')[0].ToLowerInvariant()
    if ($expectedHash -notmatch '^[0-9a-f]{64}$') {
        throw 'release checksum is invalid'
    }
    $actualHash = (Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $expectedHash) {
        throw 'release checksum verification failed'
    }

    & $cosignCommand verify-blob --bundle $signatureBundle `
        --certificate-identity "https://github.com/$($script:Repository)/.github/workflows/release.yml@refs/tags/v$($script:Version)" `
        --certificate-oidc-issuer https://token.actions.githubusercontent.com `
        $archive
    if ($LASTEXITCODE -ne 0) {
        throw 'release signature verification failed'
    }

    Expand-Archive -LiteralPath $archive -DestinationPath $script:StagingDirectory
    $installer = Join-Path $script:StagingDirectory "project-mindflayer-$($script:Version)-windows/install.ps1"
    if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
        throw 'verified release does not contain install.ps1'
    }
    & $installer @PSBoundParameters
    if ($LASTEXITCODE -ne 0) {
        throw "installer failed with exit code $LASTEXITCODE"
    }
}
finally {
    if (Test-Path -LiteralPath $script:StagingDirectory) {
        Remove-Item -LiteralPath $script:StagingDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}
