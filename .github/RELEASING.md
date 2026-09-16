# Releasing (maintainers)

Two GitHub Actions workflows live in this folder:

| Workflow | Trigger | What it does |
| --- | --- | --- |
| `workflows/release-ipa.yml` | Publishing a GitHub release (or manual run) | Builds an unsigned Release IPA, uploads it as a workflow artifact and attaches it to the release. The version comes from the tag (`v1.2.3` → `1.2.3`). No secrets required. |
| `workflows/testflight.yml` | 1st of each month at 14:00 UTC (or manual run) | Archives a signed build and uploads it to App Store Connect / TestFlight. Skips automatically if there were no commits in the last month (tick *force* on a manual run to override). |

## Cutting a release

1. Tag the commit with a version, e.g. `v1.1.0`, and push the tag.
2. Create a GitHub release from that tag. When it is **published**, the workflow builds and attaches `Brokenithm-SwiftUI-1.1.0-unsigned.ipa` plus a `.sha256`.

## One-time TestFlight setup

The monthly TestFlight job needs five repository secrets (Settings → Secrets and variables → Actions → *New repository secret*). They are only used from `env:` blocks, masked in logs, and never written to artifacts.

| Secret | Value |
| --- | --- |
| `APP_STORE_CONNECT_KEY_ID` | Key ID of an App Store Connect API key (Users and Access → Integrations → App Store Connect API). The key needs the **App Manager** or **Admin** role so it can create provisioning profiles. |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID shown on the same page. |
| `APP_STORE_CONNECT_PRIVATE_KEY` | The full text of the downloaded `AuthKey_XXXXXXXXXX.p8` file (including the BEGIN/END lines). |
| `DISTRIBUTION_CERTIFICATE_P12` | Your **Apple Distribution** certificate *and* private key exported from Keychain Access as a `.p12`, then base64-encoded (see the command below the table). |
| `DISTRIBUTION_CERTIFICATE_PASSWORD` | The password you chose when exporting the `.p12`. |

To base64-encode the certificate and copy it to the clipboard:

```bash
base64 -i Certificates.p12 | pbcopy
```

Notes:

- The build number is a UTC timestamp (`YYYYMMDDHHMM`), so it always increases and never collides with a build uploaded from Xcode. The marketing version is taken from the latest `vX.Y.Z` tag, falling back to the project's `MARKETING_VERSION`.
- `ITSAppUsesNonExemptEncryption` is already `false` in `Info.plist`, so uploads do not get stuck on the export-compliance question.
- The distribution certificate expires yearly; when it does, export a new `.p12` and update the two certificate secrets.
- Run the TestFlight workflow manually once after adding the secrets to confirm signing works before the first scheduled run.
