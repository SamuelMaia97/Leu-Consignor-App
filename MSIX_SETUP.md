# Leu Consignor App — Windows MSIX test deployment

This project is configured to create a Windows `.msix` installer for **Leu Consignor App**.

## 1. Create the test signing certificate

From the project root, in PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\create-msix-test-certificate.ps1
```

This generates:

```text
certs\LeuConsignorAppTestCert.pfx   # private signing certificate; keep private
certs\LeuConsignorAppTestCert.cer   # public certificate; safe to send to testers
```

The certificate subject is:

```text
CN=Leu Numismatik AG, O=Leu Numismatik AG, C=CH
```

This must exactly match `msix_config.publisher` in `pubspec.yaml`.

## 2. Create the MSIX installer

Run:

```powershell
flutter pub get
flutter build windows --release
dart run msix:create
```

The installer output is:

```text
build\windows\installer\LeuConsignorApp.msix
```

## 3. What to send to a tester

Send these files:

```text
LeuConsignorApp.msix
LeuConsignorAppTestCert.cer
install-msix-test-certificate.ps1
```

Do **not** send:

```text
LeuConsignorAppTestCert.pfx
```

The `.pfx` contains the private signing key.

## 4. Tester install steps

On the tester's computer, put the three files in the same folder.

Open PowerShell **as Administrator** and run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install-msix-test-certificate.ps1
```

Then install the app either by double-clicking:

```text
LeuConsignorApp.msix
```

or by running:

```powershell
Add-AppxPackage .\LeuConsignorApp.msix
```

## Notes

This setup is for internal testing / sideloading. For public customer distribution, use Microsoft Store signing or a production code-signing certificate / signing service.
