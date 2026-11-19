# Releasing (maintainers)

Two GitHub Actions workflows live in this folder:

| Workflow | Trigger | What it does |
| --- | --- | --- |
| `workflows/release-ipa.yml` | Publishing a GitHub release (or manual run) | Builds an unsigned Release IPA, uploads it as a workflow artifact and attaches it to the release. The version comes from the tag (`v1.2.3` → `1.2.3`). No secrets required. |
| `workflows/testflight.yml` | 1st of each month at 14:00 UTC (or manual run) | Archives a signed build and uploads it to App Store Connect / TestFlight. Skips automatically if there were no commits in the last month (tick *force* on a manual run to override). |

## Cutting a release

1. Tag the commit with a version, e.g. `v1.1.0`, and push the tag.
2. Create a GitHub release from that tag. When it is **published**, the workflow builds and attaches `Brokenithm-SwiftUI-1.1.0-unsigned.ipa` plus a `.sha256`.

## How the TestFlight job signs

The pipeline mirrors the AzuraCast Radio repo. The archive is signed **manually** with an Apple Distribution certificate from secrets. The App Store provisioning profile is fetched, or created, by the fastlane `provision` lane in `fastlane/Fastfile` through the App Store Connect API, using the same API key. The lane matches the portal certificate to the one in the CI keychain by serial number, switches the app target to manual signing for Release, and reports the profile name to the Export step, which writes it into `.github/ExportOptions.plist`. The `beta` lane then uploads with `pilot`, waits for Apple to process the build, and distributes it.

This deliberately avoids Xcode's automatic cloud signing on CI. That path needs an Admin API key with *Access to Cloud Managed Distribution Certificate* and otherwise fails at export with `Cloud signing permission error` / `No profiles for 'com.ocramer.brokenithm-swiftui' were found`.

## One-time TestFlight setup

Add these repository secrets (Settings → Secrets and variables → Actions → *New repository secret*). They are only used from `env:` blocks, masked in logs, and never written to artifacts. The names match the AzuraCast Radio repo so the same values can be reused; the older `DISTRIBUTION_CERTIFICATE_*` names still work as aliases.

| Secret | Value |
| --- | --- |
| `APP_STORE_CONNECT_KEY_ID` | Key ID of an App Store Connect API key (Users and Access → Integrations → App Store Connect API). **App Manager** or **Admin** role. |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID shown on the same page. |
| `APP_STORE_CONNECT_PRIVATE_KEY` | The downloaded `AuthKey_XXXXXXXXXX.p8`. Either the raw PEM text (including the BEGIN/END lines) or its base64 encoding; both are accepted. |
| `BUILD_CERTIFICATE_BASE64` | Your **Apple Distribution** certificate *and* private key exported from Keychain Access as a `.p12`, then base64-encoded (see *Exporting the certificate* below). Alias: `DISTRIBUTION_CERTIFICATE_P12`. |
| `P12_PASSWORD` | The password you chose when exporting the `.p12`. Alias: `DISTRIBUTION_CERTIFICATE_PASSWORD`. |
| `KEYCHAIN_PASSWORD` | Optional. Password for the throwaway CI keychain. A random one is generated when unset. |

Repository **variable** (not secret), under the *Variables* tab on the same page:

| Variable | Value |
| --- | --- |
| `TESTFLIGHT_GROUPS` | Comma-separated names of the external tester groups to distribute to, e.g. `External`. The public TestFlight invite link belongs to an external group, so set this or monthly builds only reach internal testers. External distribution goes through Beta App Review on each new version string. |

### Exporting the certificate

The `.p12` must contain the **private key**, not just the certificate. A certificate-only export imports without error but the workflow then fails with `no Apple Distribution identity`.

1. Open **Keychain Access**, choose the **login** keychain and the **My Certificates** category.
2. Find `Apple Distribution: <your name> (63LV533T6V)`. It must have a disclosure triangle with a private key underneath. If there are several, any one with a key works; the `provision` lane matches the portal certificate to whichever you export.
3. Expand it, select **both** the certificate and the private key, right-click → **Export 2 items…**, choose the `.p12` format and set a password. That password is `P12_PASSWORD`.
4. Confirm the file contains a key (should print `1` or more):

```bash
openssl pkcs12 -in Certificates.p12 -nocerts -nodes | grep -c "PRIVATE KEY"
```

5. Base64-encode it and copy to the clipboard, then paste as `BUILD_CERTIFICATE_BASE64`:

```bash
base64 -i Certificates.p12 | pbcopy
```

Notes:

- The build number is a UTC timestamp (`YYYYMMDDHHMM`), so it always increases and never collides with a build uploaded from Xcode. The marketing version is taken from the latest `vX.Y.Z` tag, falling back to the project's `MARKETING_VERSION`.
- The job runs on `macos-26` with the latest **stable** Xcode. Apple rejects uploads built with a beta Xcode during processing, so do not switch it to a beta image to match the local toolchain.
- `ITSAppUsesNonExemptEncryption` is already `false` in `Info.plist`, so uploads do not get stuck on the export-compliance question.
- The distribution certificate expires yearly; when it does, export a new `.p12` and update the two certificate secrets.
- Run the TestFlight workflow manually once after adding the secrets to confirm signing works before the first scheduled run. Untick *external* on that run to skip Beta App Review.
