param(
    [string]$MsixPath = "",
    [string]$CertificatePath = ""
)

$ErrorActionPreference = "Stop"

function Resolve-InstallerPath {
    param(
        [string]$ExplicitPath,
        [string]$DefaultFileName
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        return (Resolve-Path -LiteralPath $ExplicitPath).Path
    }

    $scriptDir = Split-Path -Parent $MyInvocation.ScriptName
    $candidate = Join-Path $scriptDir $DefaultFileName
    if (Test-Path -LiteralPath $candidate) {
        return (Resolve-Path -LiteralPath $candidate).Path
    }

    throw "Could not find $DefaultFileName. Pass the path explicitly."
}

$msix = Resolve-InstallerPath -ExplicitPath $MsixPath -DefaultFileName "LeuConsignorApp.msix"
$cert = Resolve-InstallerPath -ExplicitPath $CertificatePath -DefaultFileName "LeuConsignorAppTestCert.cer"

$signature = Get-AuthenticodeSignature -LiteralPath $msix
if ($signature.SignerCertificate -eq $null) {
    throw "The MSIX is not signed: $msix"
}

$certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($cert)
if ($signature.SignerCertificate.Thumbprint -ne $certificate.Thumbprint) {
    throw "Certificate thumbprint does not match the MSIX signature. MSIX=$($signature.SignerCertificate.Thumbprint), CER=$($certificate.Thumbprint)"
}

Write-Host "Installing certificate $($certificate.Thumbprint) into LocalMachine Root..."
Import-Certificate -FilePath $cert -CertStoreLocation Cert:\LocalMachine\Root | Out-Null

Write-Host "Installing certificate $($certificate.Thumbprint) into LocalMachine TrustedPeople..."
Import-Certificate -FilePath $cert -CertStoreLocation Cert:\LocalMachine\TrustedPeople | Out-Null

Write-Host "Installing MSIX..."
Add-AppxPackage -Path $msix

Write-Host "Done."
