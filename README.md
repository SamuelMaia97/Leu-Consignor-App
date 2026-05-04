# Leu Consignor App

Leu Consignor App is a Flutter application for managing Leu Numismatik consignors and consignor contracts. It supports local draft work, Microsoft sign-in, backend synchronization, customer lookup, auction selection, file capture/upload, and backend-rendered contract PDFs.

The app is designed for operational use on desktop/mobile devices, with particular support for Windows builds and MSIX test deployment.

## Table of contents

- [Features](#features)
- [Technology stack](#technology-stack)
- [Project structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Clone the repository](#clone-the-repository)
- [Install dependencies](#install-dependencies)
- [Run the app locally](#run-the-app-locally)
- [Initial login and users](#initial-login-and-users)
- [Configuration](#configuration)
- [API authentication](#api-authentication)
- [API endpoints](#api-endpoints)
- [Local storage and generated files](#local-storage-and-generated-files)
- [Testing and code quality](#testing-and-code-quality)
- [Build and packaging](#build-and-packaging)
- [Security notes](#security-notes)
- [Troubleshooting](#troubleshooting)

## Features

- **Dashboard** with quick actions for consignor creation, contract creation, list views, sync, and configuration.
- **Local app lock** with local users stored through secure storage.
- **Consignor management** for individuals and legal entities.
- **Customer lookup** against the backend to prefill existing customer data.
- **Contract workflow** with auction selection, passport/ID files, product images, registration files, PDF review, and signature capture.
- **PDF generation** delegated to the backend contract renderer while Flutter handles UI, validation, signatures, preview, local saving, and uploads.
- **Offline-first local drafts** using Hive boxes for consignors, contracts, settings, and wizard drafts.
- **Backend synchronization** for consignors, contracts, uploads, phone prefixes, and auction dropdown data.
- **Microsoft OAuth sign-in** using a loopback authorization-code flow with PKCE.
- **Windows MSIX packaging** with a test certificate workflow for internal sideloading.

## Technology stack

- **Flutter / Dart**
- **Provider** for application state
- **go_router** for navigation
- **Dio** for HTTP API calls
- **Hive** and **Hive Flutter** for local storage
- **flutter_secure_storage** for local app-lock users and API token storage
- **file_picker**, **image_picker**, and **camera** for file/camera workflows
- **pdf**, **printing**, and **open_filex** for local PDF/file handling
- **msix** for Windows installer packaging

The project requires Dart SDK `>=3.5.0 <4.0.0` as declared in `pubspec.yaml`.

## Project structure

```text
lib/
  main.dart                         # App entry point
  src/app.dart                      # Router and root MaterialApp
  src/application/                  # Application-level PDF/template services
  src/data/                         # API client and PDF render payloads
  src/domain/                       # Domain enums and helpers
  src/models/                       # Consignor, contract, settings, address, banking, etc.
  src/repositories/                 # Hive-backed repositories
  src/screens/                      # Dashboard, lists, editors, wizard, settings, users
  src/services/                     # API, auth, app lock, files, PDF generation
  src/state/                        # AppState and sync orchestration
  src/storage/                      # Local Hive store setup
  src/theme/                        # App theme
  src/utils/                        # Validators and helper utilities
  src/widgets/                      # Shared UI components

assets/
  data/                             # Bundled countries and phone prefixes
  images/                           # Leu branding assets
  signatures/                       # Leu representative signature assets

scripts/
  create-msix-test-certificate.ps1
  install-msix-test-certificate.ps1

test/                               # Unit/widget tests
```

## Prerequisites

Install the following before running the project:

1. **Flutter stable** with Dart SDK support for `>=3.5.0 <4.0.0`.
2. **Git**.
3. **Visual Studio 2022 / Build Tools with Desktop development with C++** for Windows desktop builds.
4. **Android Studio or Android SDK** for Android builds.
5. **Java 17** for Android/Gradle builds.
6. **Xcode** for iOS builds on macOS.
7. Network/VPN access to the backend API host.
8. Microsoft Entra ID / Azure AD app registration configured for the OAuth client used by the app.

Check your local Flutter setup:

```bash
flutter doctor
```

## Clone the repository

Replace `<repository-url>` with the actual Git remote URL for this project:

```bash
git clone <repository-url>
cd Leu-Consignor-App
```

If you are starting from a ZIP export instead of Git:

```bash
unzip Leu-Consignor-App.zip
cd Leu-Consignor-App
```

Recommended cleanup before committing a repository created from this ZIP:

```bash
rm -rf .dart_tool build android/.gradle android/.kotlin
```

The `.gitignore` already excludes common Flutter build outputs and the private MSIX `.pfx` signing certificate.

## Install dependencies

```bash
flutter pub get
```

## Run the app locally

### Windows

```bash
flutter run -d windows
```

### Android emulator

For local IIS Express development, Android emulators usually access the host machine through `10.0.2.2` instead of `localhost`.

```bash
flutter run -d android
```

### iOS simulator

```bash
flutter run -d ios
```

### Web

```bash
flutter run -d chrome
```

Microsoft sign-in is currently implemented for desktop/mobile loopback flows and is not fully supported for Flutter Web in this project without adding a web callback/proxy flow.

## Initial login and users

The app opens with a local lock screen before showing the main application.

- The built-in administrator username is `admin`.
- The seeded development password is defined in `lib/src/services/app_lock_service.dart`.
- Change the default password immediately for any shared environment.
- The administrator can manage local app users from the **Users** screen.
- Non-admin users can use the saved API/OAuth configuration but cannot edit admin-managed settings.

Local app users are independent from Microsoft API authentication. The app lock controls local access to the application; Microsoft sign-in controls access to the backend API.

## Configuration

Open **Settings** in the app and configure the API and Microsoft OAuth values.

### API settings

The main value is:

| Setting | Description |
| --- | --- |
| API base URL | Backend host, for example `https://api.example.com` or local development URL. |

The app requires an API base URL with a scheme. In release builds, and for non-local hosts, HTTPS is required.

Local development hosts allowed in debug mode include:

- `localhost`
- `127.0.0.1`
- `::1`
- `10.0.2.2`

The app contains debug-only certificate relaxation for local IIS Express HTTPS on port `44364` for `localhost` or `10.0.2.2`.

### Microsoft OAuth settings

Default OAuth fields are stored in `AppSettings` and can be edited in the admin settings UI:

| Setting | Purpose |
| --- | --- |
| OAuth client ID | Microsoft Entra application/client ID. |
| OAuth tenant ID | Microsoft Entra tenant ID. |
| OAuth scope | API scope requested by the app. |
| OAuth redirect URI | Loopback redirect URI, for example `http://localhost:<port>`. |

The OAuth implementation uses authorization code flow with PKCE and opens the Microsoft login page in the system browser.

## API authentication

All backend API requests are sent with this header when a token is available:

```http
Authorization: Bearer <access-token>
```

The token is obtained through Microsoft sign-in or pasted manually in Settings. The app checks the JWT expiry and clears expired tokens.

## API endpoints

The app uses the configured API base URL plus the endpoint paths below. Several paths are configurable in `AppSettings`; others are currently hard-coded in `ApiService`.

### Configurable endpoints

| Method | Default path | Used for | Query/body notes |
| --- | --- | --- | --- |
| `GET` | `/api/consignors-app/consignors/get-all` | Validate connection and fetch remote consignor summaries. | Optional query parameter: `sinceUtc=<UTC ISO timestamp>` for incremental sync. |
| `GET` | `/api/consignors-app/consignors/get/{id}` | Fetch one consignor with contract groups/files. | `{id}` is the backend consignor ID. |
| `PUT` | `/api/consignors-app/consignors/update/{id}` | Update an existing backend consignor. | Body is `Consignor.toJson()`. |
| `POST` | `/api/consignors-app/consignors/bulk-create` | Create one or more new consignors. | Body is an array of `Consignor.toJson()` objects. |
| `GET` | `/api/consignors-app/files/get-all` | Configured legacy/all-files endpoint. | Present in settings; not heavily used by current sync flow. |
| `GET` | `/api/consignors-app/files/get/{id}` | Configured single-file endpoint. | Present in settings; not heavily used by current sync flow. |
| `PUT` | `/api/consignors-app/files/update/{id}` | Configured file update endpoint. | Present in settings; current upload updates use the hard-coded upload endpoint below. |
| `POST` | `/api/consignors-app/files/bulk-create` | Configured bulk file create endpoint. | Present in settings; current contract creation uses the hard-coded contract endpoint below. |
| `GET` | `/api/consignors-app/origins/prefixes` | Fetch phone/country prefixes from the backend. | Falls back to bundled phone prefixes if needed. |
| `GET` | `/api/consignors-app/customers/search` | Search existing customers for lookup/prefill. | Query parameters: `q=<search text>`, `take=<max results>`. |

### Hard-coded endpoints currently used by the app

| Method | Path | Used for | Query/body notes |
| --- | --- | --- | --- |
| `GET` | `/api/consignors-app/auctions/dropdown` | Fetch auction dropdown options. | Expects an array of auction objects. |
| `POST` | `/api/consignors-app/contracts/render-pdf` | Render the official contract PDF from app data. | Body contains template version, record, consignor, representative/owner, signatures, attachments, and flags. Response is PDF bytes. |
| `POST` | `/api/consignors-app/consignors/{consignorId}/contracts` | Create/sync a contract group with files for a consignor and auction. | Body contains `consignorId`, `auctionId`, optional `signedAt`, and `files`. |
| `PUT` | `/api/consignors-app/consignors/{consignorId}/uploads/{uploadId}` | Replace/update an existing upload. | Body is an upload payload with Base64 `fileData`. |
| `DELETE` | `/api/consignors-app/consignors/{consignorId}/uploads/{uploadId}` | Delete an existing upload. | No request body. |
| `POST` | `/api/consignors-app/consignors/{consignorId}/contracts/{auctionId}/sync` | Refresh/sync one contract group after remote changes. | No request body. Response is a contract group. |

### Additional template API client

The repository also contains `ContractTemplateApiClient`, which posts to:

| Method | Path | Used for |
| --- | --- | --- |
| `POST` | `/api/consignor-contracts/render-pdf` | Alternative/template-based contract PDF rendering client. |

The currently wired contract PDF flow in `ContractPdfService` uses `/api/consignors-app/contracts/render-pdf` through `ApiService`.

### Expected payload concepts

#### Consignor payload

`Consignor.toJson()` includes fields such as:

- `id`
- `systemReferenceConsignor`
- `systemReferenceCustomer`
- `existingCustomerId`
- `isLegalEntity`
- `consignorType`
- `tradingName`
- `consignorInfo`
- `vatLiability`
- `vatNumber`
- `phonePrefix`
- `phonePrefixOriginId`
- `phoneNumber`
- `emailAddress`
- `consignorAddress`
- `bankingDetails`
- `paymentOption`
- newsletter/collecting-area flags
- audit and sync metadata

#### Upload payload

Contract upload payloads include:

- `localId`
- `fileId`
- `auctionId`
- `fileType`
- `fileName`
- `fileData` as Base64
- `signedAt`
- `lastModifiedUtc`

Upload type values:

| Value | Meaning |
| --- | --- |
| `1` | Passport / ID image |
| `2` | Agreement / registration file |
| `3` | Product image |

#### PDF render payload

The `/api/consignors-app/contracts/render-pdf` endpoint receives:

- `templateVersion`
- `record`
- `consignor`
- optional `authorizedRepresentative`
- optional `beneficialOwner`
- `consignorType`
- `consignorIsOwner`
- auction and commission fields
- Leu representative fields
- signature images as Base64 PNG
- attachments with Base64 file data
- `saveToUploads`

The endpoint should respond with raw PDF bytes.

## Local storage and generated files

The app initializes Hive in the user documents directory under:

```text
<Documents>/Consignor App
```

It creates these Hive boxes:

| Box | Purpose |
| --- | --- |
| `consignors` | Local consignor records and drafts. |
| `contracts` | Local contract records and uploads. |
| `settings` | API/OAuth settings and stored API token. |
| `wizard_drafts` | In-progress wizard state. |

Generated and imported files are stored below the same application directory:

```text
Consignor App/
  Contracts/
  Pictures/
    ID/
    Products/
```

## Testing and code quality

Run unit and widget tests:

```bash
flutter test
```

Run static analysis:

```bash
flutter analyze
```

Run dependency resolution checks:

```bash
flutter pub get
flutter pub outdated
```

## Build and packaging

### Windows debug/release build

```bash
flutter build windows --release
```

The Windows executable is built under:

```text
build/windows/x64/runner/Release/
```

### Windows MSIX package

The project has `msix_config` in `pubspec.yaml` and helper scripts for test certificates.

Create a test signing certificate:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\create-msix-test-certificate.ps1
```

Build the Windows release and MSIX package:

```powershell
flutter pub get
flutter build windows --release
dart run msix:create
```

Expected MSIX output:

```text
build\windows\installer\LeuConsignorApp.msix
```

Install the public test certificate on a tester machine from an elevated PowerShell window:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\install-msix-test-certificate.ps1
```

Then install the app:

```powershell
Add-AppxPackage .\LeuConsignorApp.msix
```

> Note: `MSIX_SETUP.md` references `scripts/build-msix.ps1`, but that script is not present in the uploaded project. Use the manual build commands above or add the missing build script.

### Android build

```bash
flutter build apk --release
```

Before production release, update the placeholder Android package name in `android/app/build.gradle.kts`:

```text
com.example.leu_consignor_app
```

Also configure a production Android signing key instead of the debug signing config.

### iOS build

```bash
flutter build ios --release
```

Configure the Apple bundle identifier, signing team, and provisioning profiles before release.

## Security notes

- Do not commit production credentials, access tokens, private keys, or `.pfx` certificates.
- The repository ZIP contains MSIX certificate material under `certs/`; rotate and replace this for real deployment.
- Keep `certs/*.pfx` private. The `.cer` file can be shared with testers for sideloading trust.
- Replace test signing with production code signing before distributing outside internal testing.
- Change the default local admin password immediately.
- Review `pubspec.yaml` MSIX certificate configuration before committing or publishing.
- API base URLs should use HTTPS outside local development.
- Backend APIs should validate the Microsoft access token and expected API scope.
- File uploads are sent as Base64 payloads, so ensure backend size limits and validation are configured.

## Troubleshooting

### `API base URL is empty`

Open **Settings** and enter the backend API base URL.

### `API base URL must include an https:// scheme`

Use a full URL including the scheme, for example:

```text
https://api.example.com
```

For local debug development only, localhost HTTP URLs may be accepted.

### `No bearer token is set`

Sign in with Microsoft from **Settings** or paste a valid API bearer token.

### `Authentication failed (401/403)`

Check that:

- the token is not expired;
- the Microsoft tenant/client/scope settings are correct;
- the backend API accepts the configured scope;
- the current user has access to the API.

### Browser/network errors in Flutter Web

The app is primarily wired for desktop/mobile API access. Browser requests may fail because of CORS, certificate, DNS, or blocked request issues. Test the Windows build first.

### Android emulator cannot reach local API

Use the emulator host alias:

```text
https://10.0.2.2:<port>
```

instead of:

```text
https://localhost:<port>
```

### Local IIS Express certificate issues

Debug builds include a special case for `https://localhost:44364` and `https://10.0.2.2:44364`. For other local ports or production builds, configure a trusted certificate.

### MSIX install fails because certificate is untrusted

Install the `.cer` certificate into `LocalMachine\TrustedPeople` using the provided elevated PowerShell script before installing the `.msix`.

## Maintenance checklist

Before production deployment:

- [ ] Replace default local admin credentials.
- [ ] Remove or rotate test certificates.
- [ ] Remove private `.pfx` files from the repository.
- [ ] Confirm API base URL and Microsoft OAuth settings.
- [ ] Confirm backend token validation and scope checks.
- [ ] Add the missing `scripts/build-msix.ps1` or update `MSIX_SETUP.md`.
- [ ] Replace Android placeholder application ID.
- [ ] Configure production signing for Android, iOS, and Windows.
- [ ] Run `flutter analyze` and `flutter test`.
- [ ] Build and smoke-test Windows, Android, and any other supported target platforms.
