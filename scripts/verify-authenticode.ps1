# Silicon LogiX / SLX CellProof
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$Thumbprint)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$signature=Get-AuthenticodeSignature -LiteralPath $Path
if($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Thumbprint -ne $Thumbprint){throw 'Binary signature is invalid or from a different signer'}
Write-Output 'Authenticode signature verified'
