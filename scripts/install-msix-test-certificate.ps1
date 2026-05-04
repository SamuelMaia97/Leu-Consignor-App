# Run this script in an elevated/admin PowerShell window on the tester's computer.
# It imports the public .cer certificate so Windows trusts the test-signed MSIX package.

#Requires -RunAsAdministrator

param(
    [string]$CerPath = ".\LeuConsignorAppTestCert.cer"
)

$ErrorActionPreference = "Stop"

if (!(Test-Path $CerPath)) {
    throw "Certificate file not found: $CerPath"
}

Write-Host "Importing $CerPath into LocalMachine\TrustedPeople..."
Import-Certificate `
    -FilePath $CerPath `
    -CertStoreLocation "Cert:\LocalMachine\TrustedPeople" | Out-Null

Write-Host "Certificate installed. You can now double-click the .msix or run:"
Write-Host "  Add-AppxPackage .\LeuConsignorApp.msix"
