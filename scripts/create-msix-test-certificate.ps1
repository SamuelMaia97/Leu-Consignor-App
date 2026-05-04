param(
    [System.Security.SecureString]$PfxPassword,
    [string]$OutputDir
)

$ErrorActionPreference = "Stop"

# Resolve project root based on this script being inside:
# C:\repos\Leu-Consignor-App\scripts
$ScriptDir = $PSScriptRoot
$ProjectRoot = Split-Path -Parent $ScriptDir

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $ProjectRoot "certs"
}

if (-not $PfxPassword) {
    $PfxPassword = Read-Host "Enter password for LeuConsignorAppTestCert.pfx" -AsSecureString
}

# This subject MUST exactly match msix_config.publisher in pubspec.yaml.
$CertSubject = "CN=Leu Numismatik AG, O=Leu Numismatik AG, C=CH"
$FriendlyName = "Leu Consignor App MSIX Test Certificate"

$PfxPath = Join-Path $OutputDir "LeuConsignorAppTestCert.pfx"
$CerPath = Join-Path $OutputDir "LeuConsignorAppTestCert.cer"

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

Write-Host "Project root: $ProjectRoot"
Write-Host "Certificate output directory: $OutputDir"
Write-Host ""
Write-Host "Creating self-signed MSIX test certificate..."

$cert = New-SelfSignedCertificate `
    -Type Custom `
    -KeyUsage DigitalSignature `
    -KeyExportPolicy Exportable `
    -KeyAlgorithm RSA `
    -KeyLength 2048 `
    -HashAlgorithm SHA256 `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3", "2.5.29.19={text}") `
    -Subject $CertSubject `
    -FriendlyName $FriendlyName `
    -NotAfter (Get-Date).AddYears(3)

Write-Host "Exporting private signing certificate to $PfxPath"

Export-PfxCertificate `
    -Cert $cert `
    -FilePath $PfxPath `
    -Password $PfxPassword | Out-Null

Write-Host "Exporting public certificate to $CerPath"

Export-Certificate `
    -Cert $cert `
    -FilePath $CerPath | Out-Null

Write-Host ""
Write-Host "Created:"
Write-Host "  $PfxPath  <- private signing cert; keep this private"
Write-Host "  $CerPath  <- public cert; send this to testers with the .msix"
Write-Host ""
Write-Host "Next: run .\scripts\build-msix.ps1 from the project root"