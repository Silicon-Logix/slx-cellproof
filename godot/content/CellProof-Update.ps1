# Silicon LogiX / SLX CellProof
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

param(
    [Parameter(Mandatory=$true)][string]$InstallerPath,
    [Parameter(Mandatory=$true)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedSha256,
    [ValidatePattern('^([a-fA-F0-9]{40})?$')][string]$ExpectedThumbprint='',
    [int]$ParentProcessId=0,
    [switch]$AllowUnsignedPreview,
    [switch]$VerifyOnly
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Test-PreparedInstaller {
    $file=Get-Item -LiteralPath $InstallerPath
    if($file.PSIsContainer -or $file.Extension -ne '.exe' -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)){
        throw 'Installer must be an ordinary executable file'
    }
    $digest=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    if($digest -ne $ExpectedSha256){throw 'Installer checksum mismatch'}
    $signature=Get-AuthenticodeSignature -LiteralPath $file.FullName
    if(-not $AllowUnsignedPreview){
        if(-not $ExpectedThumbprint){throw 'Production updates require a pinned publisher thumbprint'}
        if($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Thumbprint -ne $ExpectedThumbprint){
            throw 'Publisher signature invalid or does not match the signed release manifest'
        }
    } elseif($signature.Status -notin @('Valid','NotSigned')) {
        throw 'Installer has an invalid existing signature'
    }
    return $file.FullName
}
try {
    $prepared=Test-PreparedInstaller
    if($VerifyOnly){
        [pscustomobject]@{Sha256Verified=$true;PublisherRequired=(-not $AllowUnsignedPreview);Executed=$false} | ConvertTo-Json -Compress
        exit 0
    }
    if($ParentProcessId -le 0 -or $ParentProcessId -eq $PID){throw 'A valid parent application process is required'}
    $parent=Get-Process -Id $ParentProcessId -ErrorAction SilentlyContinue
    if($parent -and -not $parent.WaitForExit(60000)){throw 'Close CellProof before installing the update'}
    $prepared=Test-PreparedInstaller
    # The user explicitly chose installation; the installer is interactive.
    $installer=Start-Process -FilePath $prepared -ArgumentList @('/SP-','/NORESTART') -PassThru
    $installer.WaitForExit()
    if($installer.ExitCode -ne 0){throw ('Installer returned exit code '+$installer.ExitCode)}
} catch {
    $message=$_.Exception.Message
    $log=Join-Path (Split-Path -Parent $InstallerPath) 'update-error.log'
    [IO.File]::WriteAllText($log,$message)
    Write-Error $message
    exit 1
}
